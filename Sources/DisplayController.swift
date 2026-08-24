import Foundation
import AppKit
import Combine
import CoreGraphics

// MARK: - Probing (off the main thread)

/// A display plus everything we learned by actually talking to it. Probing costs a few
/// hundred milliseconds per monitor, so it never runs on the main thread.
struct ProbedDisplay {
    let discovered: DiscoveredDisplay
    let link: DDCLink?
    let brightness: UInt16?
    let brightnessMax: UInt16
    let contrast: UInt16?
    let contrastMax: UInt16
    let volume: UInt16?
    let volumeMax: UInt16
    let muted: Bool?
    /// False when the kernel refuses to carry I²C traffic for this display at all. Such a
    /// display gets no slider — dragging one would silently do nothing.
    let busUsable: Bool
}

enum DisplayProber {

    /// Enumerates and interrogates every online display. Call from a background queue.
    static func probeAll() -> [ProbedDisplay] {
        DisplayRegistry.discover().map { discovered in
            if discovered.isBuiltIn {
                return ProbedDisplay(
                    discovered: discovered,
                    link: nil,
                    brightness: BuiltInBrightness.isAvailable ? BuiltInBrightness.read(discovered.displayID) : nil,
                    brightnessMax: 100,
                    contrast: nil,
                    contrastMax: 100,
                    volume: nil,
                    volumeMax: 100,
                    muted: nil,
                    busUsable: BuiltInBrightness.isAvailable
                )
            }

            guard let service = discovered.avService, ddcRuntimeAvailable else {
                return ProbedDisplay(discovered: discovered, link: nil, brightness: nil,
                                     brightnessMax: 100, contrast: nil, contrastMax: 100,
                                     volume: nil, volumeMax: 100, muted: nil, busUsable: false)
            }

            let link = DDCLink(avService: service, label: discovered.framebufferKey)
            let brightnessProbe = link.probeSync(.brightness)

            // A refused bus is final: skip the contrast probe and offer no controls.
            if case .busUnavailable = brightnessProbe {
                return ProbedDisplay(discovered: discovered, link: nil, brightness: nil,
                                     brightnessMax: 100, contrast: nil, contrastMax: 100,
                                     volume: nil, volumeMax: 100, muted: nil, busUsable: false)
            }

            var brightness: UInt16?
            var brightnessMax: UInt16 = 100
            if case .value(let current, let max) = brightnessProbe {
                brightness = current
                brightnessMax = max
            }
            let contrast = link.readSync(.contrast)
            let volume = link.readSync(.speakerVolume)
            let mute = link.readSync(.audioMute)
            return ProbedDisplay(
                discovered: discovered,
                link: link,
                brightness: brightness,
                brightnessMax: brightnessMax,
                contrast: contrast?.current,
                contrastMax: contrast?.max ?? 100,
                volume: volume?.current,
                volumeMax: volume?.max ?? 100,
                muted: mute.map { $0.current == AudioMuteState.muted.rawValue },
                busUsable: true
            )
        }
    }
}

// MARK: - One controllable display

enum ControlBackend {
    case ddc(DDCLink)
    case builtIn
    /// No reachable DDC channel — the image is darkened instead of the backlight.
    case software
    case unavailable
}

@MainActor
final class ManagedDisplay: ObservableObject, Identifiable {

    let id: CGDirectDisplayID
    let name: String
    let serialText: String
    let backend: ControlBackend
    let brightnessMax: UInt16
    let contrastMax: UInt16
    let contrastSupported: Bool
    let volumeMax: UInt16
    /// Only displays that answer VCP 0x62 get audio controls; most monitors have no speakers.
    let volumeSupported: Bool
    let muteSupported: Bool

    /// True when the display answered a DDC read. Control is still offered when it did not:
    /// plenty of monitors accept Set VCP while refusing Get VCP.
    @Published private(set) var readConfirmed: Bool
    @Published var brightness: Double
    @Published var contrast: Double
    @Published var volume: Double
    @Published var isMuted: Bool

    /// Set during a rescan when two panels report the same EDID name, so the menu can
    /// tell two identical monitors apart.
    @Published var nameSuffix: String = ""

    var displayLabel: String { nameSuffix.isEmpty ? name : "\(name) (\(nameSuffix))" }

    private let storageKey: String
    private var lastSentBrightness: UInt16?
    private var lastSentContrast: UInt16?
    private var lastSentVolume: UInt16?

    init(probed: ProbedDisplay) {
        let discovered = probed.discovered
        self.id = discovered.displayID
        self.name = discovered.name
        self.serialText = discovered.serialText
        self.brightnessMax = probed.brightnessMax
        self.contrastMax = probed.contrastMax
        self.contrastSupported = probed.contrast != nil
        self.volumeMax = probed.volumeMax
        self.volumeSupported = probed.volume != nil
        self.muteSupported = probed.muted != nil
        self.readConfirmed = probed.brightness != nil

        if let link = probed.link, probed.busUsable {
            self.backend = .ddc(link)
        } else if discovered.isBuiltIn, BuiltInBrightness.isAvailable {
            self.backend = .builtIn
        } else if SoftwareDimmer.isEnabled {
            self.backend = .software
        } else {
            self.backend = .unavailable
        }

        let key = "brightness.\(discovered.name).\(discovered.serialText)"
        self.storageKey = key
        let stored = UserDefaults.standard.object(forKey: key) as? Int
        self.brightness = Double(probed.brightness ?? UInt16(stored ?? Int(probed.brightnessMax)))
        self.contrast = Double(probed.contrast ?? probed.contrastMax / 2)
        self.volume = Double(probed.volume ?? 0)
        self.isMuted = probed.muted ?? false
        self.lastSentBrightness = probed.brightness
        self.lastSentContrast = probed.contrast

        // If the channel dies while in use, drop the controls rather than keep faking them.
        if case .ddc(let link) = backend {
            link.busFailureHandler = { [weak self] in self?.busDidFail = true }
        }
        // Software dimming is ours to maintain, so re-assert the remembered value.
        if case .software = backend {
            readConfirmed = true
            SoftwareDimmer.apply(discovered.displayID, percent: brightness)
        }
    }

    /// Set when a write is refused after the fact; the menu then treats the display as
    /// uncontrollable and explains why.
    @Published private(set) var busDidFail = false

    var isControllable: Bool {
        if busDidFail { return false }
        switch backend {
        case .ddc, .builtIn, .software: return true
        case .unavailable: return false
        }
    }

    /// True when the slider darkens the image rather than the backlight, which the menu says out loud.
    var isSoftwareDimmed: Bool {
        if case .software = backend { return true }
        return false
    }

    /// How this display is being driven, in one short line for the menu header.
    var statusText: String {
        if busDidFail { return "Verbindung verloren" }
        switch backend {
        case .ddc: return readConfirmed ? "DDC/CI verbunden" : "DDC/CI, keine Rückmeldung"
        case .builtIn: return "Internes Display"
        case .software: return "Softwaredimmung"
        case .unavailable: return "Nicht steuerbar"
        }
    }

    /// Green when the backlight itself is being driven, amber when only the image is, red
    /// when nothing works. The dot carries this at a glance in the monitor list.
    enum Health { case good, partial, none }

    var health: Health {
        if busDidFail { return .none }
        switch backend {
        case .ddc: return readConfirmed ? .good : .partial
        case .builtIn: return .good
        case .software: return .partial
        case .unavailable: return .none
        }
    }

    var brightnessPercent: Int {
        guard brightnessMax > 0 else { return 0 }
        return Int((brightness / Double(brightnessMax) * 100).rounded())
    }

    var contrastPercent: Int {
        guard contrastMax > 0 else { return 0 }
        return Int((contrast / Double(contrastMax) * 100).rounded())
    }

    var volumePercent: Int {
        guard volumeMax > 0 else { return 0 }
        return Int((volume / Double(volumeMax) * 100).rounded())
    }

    // MARK: Applying values

    /// Safe to call at drag rate: redundant values are dropped here and the DDC layer
    /// coalesces whatever is left.
    func applyBrightness() {
        let value = UInt16(max(0, min(Double(brightnessMax), brightness.rounded())))
        guard value != lastSentBrightness else { return }
        lastSentBrightness = value
        UserDefaults.standard.set(Int(value), forKey: storageKey)

        switch backend {
        case .ddc(let link): link.schedule(.brightness, value: value)
        case .builtIn: BuiltInBrightness.write(id, percent: value)
        case .software: SoftwareDimmer.apply(id, percent: Double(value))
        case .unavailable: break
        }
    }

    func applyContrast() {
        guard contrastSupported, case .ddc(let link) = backend else { return }
        let value = UInt16(max(0, min(Double(contrastMax), contrast.rounded())))
        guard value != lastSentContrast else { return }
        lastSentContrast = value
        link.schedule(.contrast, value: value)
    }

    func applyVolume() {
        guard volumeSupported, case .ddc(let link) = backend else { return }
        let value = UInt16(max(0, min(Double(volumeMax), volume.rounded())))
        guard value != lastSentVolume else { return }
        lastSentVolume = value
        link.schedule(.speakerVolume, value: value)

        // Moving the slider off zero while muted should be audible, not silently ignored.
        if isMuted, value > 0 { setMuted(false) }
    }

    func setMuted(_ muted: Bool) {
        guard muteSupported, case .ddc(let link) = backend else { return }
        isMuted = muted
        link.schedule(.audioMute, value: (muted ? AudioMuteState.muted : .unmuted).rawValue)
    }

    /// Volume in sixteenths of full scale — the step size macOS itself uses for its keys.
    func stepVolume(sixteenths: Int) {
        guard volumeSupported else { return }
        let step = Double(volumeMax) / 16
        volume = max(0, min(Double(volumeMax), (volume + step * Double(sixteenths)).rounded()))
        applyVolume()
    }

    /// Nudges brightness by a percentage of full scale — used by the global hotkeys.
    func step(percent: Int) {
        let delta = Double(brightnessMax) * Double(percent) / 100
        brightness = max(0, min(Double(brightnessMax), (brightness + delta).rounded()))
        applyBrightness()
    }

    func setPercent(_ percent: Double) {
        brightness = max(0, min(100, percent)) / 100 * Double(brightnessMax)
        applyBrightness()
    }

    /// Re-reads the hardware — after wake, or when the panel was changed from its own OSD.
    func refreshFromHardware() {
        switch backend {
        case .ddc(let link):
            link.read(.brightness) { [weak self] reading in
                guard let self, let reading else { return }
                self.brightness = Double(reading.current)
                self.lastSentBrightness = reading.current
                self.readConfirmed = true
            }
        case .builtIn:
            if let value = BuiltInBrightness.read(id) {
                brightness = Double(value)
                lastSentBrightness = value
                readConfirmed = true
            }
        case .software:
            // A display reconfiguration or wake wipes the gamma table; put it back.
            SoftwareDimmer.apply(id, percent: brightness)
        case .unavailable:
            break
        }
    }
}

// MARK: - All displays

@MainActor
final class DisplayController: ObservableObject {

    static let shared = DisplayController()

    @Published private(set) var displays: [ManagedDisplay] = []
    @Published private(set) var isScanning = false

    /// Drives every controllable display from one slider.
    @Published var linkAll: Bool = UserDefaults.standard.bool(forKey: "linkAllDisplays") {
        didSet { UserDefaults.standard.set(linkAll, forKey: "linkAllDisplays") }
    }

    /// Turning this off restores every gamma table and drops the software sliders.
    @Published var softwareDimming: Bool = SoftwareDimmer.isEnabled {
        didSet {
            guard oldValue != softwareDimming else { return }
            SoftwareDimmer.isEnabled = softwareDimming
            if !softwareDimming { SoftwareDimmer.restoreAll() }
            rescan()
        }
    }

    /// Which display the detail section shows. Unset means "whichever one the pointer is on",
    /// which is the right guess until the user makes a choice of their own.
    @Published var selectedDisplayID: CGDirectDisplayID?

    private var rescanWorkItem: DispatchWorkItem?

    init() {
        rescan()
        NotificationCenter.default.addObserver(
            self, selector: #selector(screenParametersChanged),
            name: NSApplication.didChangeScreenParametersNotification, object: nil
        )
        NSWorkspace.shared.notificationCenter.addObserver(
            self, selector: #selector(systemDidWake),
            name: NSWorkspace.didWakeNotification, object: nil
        )
    }

    var controllableDisplays: [ManagedDisplay] { displays.filter(\.isControllable) }

    /// Two DELL U2719D look alike in the menu; the EDID serial is what actually distinguishes them.
    private static func disambiguateNames(of displays: [ManagedDisplay]) {
        let counts = Dictionary(grouping: displays, by: \.name).mapValues(\.count)
        for display in displays where (counts[display.name] ?? 0) > 1 {
            display.nameSuffix = display.serialText.isEmpty ? "ID \(display.id)" : display.serialText
        }
    }

    func rescan() {
        guard !isScanning else { return }
        isScanning = true
        DispatchQueue.global(qos: .userInitiated).async {
            let probed = DisplayProber.probeAll()
            DispatchQueue.main.async {
                let managed = probed.map(ManagedDisplay.init(probed:))
                Self.disambiguateNames(of: managed)
                self.displays = managed
                self.isScanning = false
            }
        }
    }

    /// The display the pointer is on, so hotkeys act on the screen actually being used.
    func displayUnderCursor() -> ManagedDisplay? {
        let location = NSEvent.mouseLocation
        if let screen = NSScreen.screens.first(where: { NSMouseInRect(location, $0.frame, false) }),
           let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber,
           let match = controllableDisplays.first(where: { $0.id == number.uint32Value }) {
            return match
        }
        return controllableDisplays.first { CGDisplayIsMain($0.id) != 0 } ?? controllableDisplays.first
    }

    var selectedDisplay: ManagedDisplay? {
        if let id = selectedDisplayID, let match = displays.first(where: { $0.id == id }) {
            return match
        }
        return displayUnderCursor() ?? controllableDisplays.first ?? displays.first
    }

    /// The display the volume keys act on: the one under the pointer when it has speakers,
    /// otherwise the only display that has any. Most setups have exactly one candidate.
    func displayForVolume() -> ManagedDisplay? {
        let candidates = controllableDisplays.filter(\.volumeSupported)
        guard !candidates.isEmpty else { return nil }
        if let under = displayUnderCursor(), candidates.contains(where: { $0.id == under.id }) {
            return under
        }
        return candidates.first
    }

    func step(percent: Int) {
        if linkAll {
            controllableDisplays.forEach { $0.step(percent: percent) }
        } else {
            displayUnderCursor()?.step(percent: percent)
        }
    }

    func setAllPercent(_ percent: Double) {
        controllableDisplays.forEach { $0.setPercent(percent) }
    }

    @objc private func screenParametersChanged() {
        // Coalesce the burst of notifications a hotplug produces.
        rescanWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.rescan() }
        rescanWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5, execute: work)
    }

    @objc private func systemDidWake() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in
            self?.displays.forEach { $0.refreshFromHardware() }
        }
    }
}
