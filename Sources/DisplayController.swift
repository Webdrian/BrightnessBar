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
    /// What the monitor said about itself, when it answers VCP 0xF3 at all.
    let capabilities: DisplayCapabilities?
    /// The input the monitor is currently showing, when it reports one.
    let inputSource: UInt8?
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
                    capabilities: nil,
                    inputSource: nil,
                    busUsable: BuiltInBrightness.isAvailable
                )
            }

            guard let service = discovered.avService, ddcRuntimeAvailable else {
                return ProbedDisplay(discovered: discovered, link: nil, brightness: nil,
                                     brightnessMax: 100, contrast: nil, contrastMax: 100,
                                     volume: nil, volumeMax: 100, muted: nil,
                                     capabilities: nil, inputSource: nil, busUsable: false)
            }

            // The EDID identity keys the cache: display IDs move between reboots, this does not.
            let identity = discovered.cacheIdentity
            let link = DDCLink(avService: service,
                               label: discovered.framebufferKey,
                               settleStep: CapabilityCache.settleIndex(for: identity) ?? 0)
            let brightnessProbe = link.probeSync(.brightness)

            // A refused bus is final: skip the contrast probe and offer no controls.
            if case .busUnavailable = brightnessProbe {
                return ProbedDisplay(discovered: discovered, link: nil, brightness: nil,
                                     brightnessMax: 100, contrast: nil, contrastMax: 100,
                                     volume: nil, volumeMax: 100, muted: nil,
                                     capabilities: nil, inputSource: nil, busUsable: false)
            }

            var brightness: UInt16?
            var brightnessMax: UInt16 = 100
            if case .value(let current, let max) = brightnessProbe {
                brightness = current
                brightnessMax = max
            }
            // Ask the monitor what it supports instead of guessing a fixed list. The string
            // costs a dozen round trips, so it is read once per monitor and cached.
            var capabilities = CapabilityCache.capabilities(for: identity)
            if capabilities == nil, !CapabilityCache.isKnownUnsupported(for: identity) {
                if let raw = link.readCapabilitiesSync(), let parsed = DisplayCapabilities(raw: raw) {
                    capabilities = parsed
                    CapabilityCache.store(parsed, for: identity)
                } else {
                    CapabilityCache.markUnsupported(for: identity)
                }
            }

            // Probe only what the monitor claims. Without a capability string every code is
            // tried, exactly as before.
            func shouldProbe(_ code: VCPCode) -> Bool {
                capabilities.map { $0.supports(code) } ?? true
            }

            let contrast = shouldProbe(.contrast) ? link.readSync(.contrast) : nil
            let volume = shouldProbe(.speakerVolume) ? link.readSync(.speakerVolume) : nil
            let mute = shouldProbe(.audioMute) ? link.readSync(.audioMute) : nil
            // Only meaningful when the monitor also listed which inputs it has; without that
            // list there is nothing to offer, and guessing could black out a screen.
            let hasInputList = !(capabilities?.values(for: .inputSource) ?? []).isEmpty
            let input = hasInputList ? link.readSync(.inputSource) : nil

            CapabilityCache.storeSettleIndex(link.learnedSettleStep, for: identity)

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
                capabilities: capabilities,
                inputSource: input.map { UInt8($0.current & 0xFF) },
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
    /// AirPlay screens carry no control channel at all — worth distinguishing from a monitor
    /// whose cable path merely swallows DDC.
    let isAirPlay: Bool
    let backend: ControlBackend
    let brightnessMax: UInt16
    let contrastMax: UInt16
    let contrastSupported: Bool
    let volumeMax: UInt16
    /// What the monitor reported about itself, if anything.
    let capabilities: DisplayCapabilities?
    /// The inputs the monitor listed, in the order it listed them. Empty when it said nothing,
    /// in which case no picker is offered — guessing at input numbers could black out a screen.
    let inputSources: [UInt8]
    /// Only displays that offer VCP 0x62 get audio controls; most monitors have no speakers.
    let volumeSupported: Bool
    let muteSupported: Bool

    /// True when the display answered a DDC read. Control is still offered when it did not:
    /// plenty of monitors accept Set VCP while refusing Get VCP.
    @Published private(set) var readConfirmed: Bool
    @Published var brightness: Double
    @Published var contrast: Double
    @Published var volume: Double
    @Published var isMuted: Bool
    @Published var currentInput: UInt8?

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
        self.isAirPlay = discovered.isAirPlay
        self.brightnessMax = probed.brightnessMax
        self.contrastMax = probed.contrastMax
        // A monitor may list a feature yet refuse to report its value. Trust the claim: a
        // slider that might work beats no slider at all.
        self.capabilities = probed.capabilities
        self.inputSources = probed.capabilities?.values(for: .inputSource) ?? []
        self.contrastSupported = probed.contrast != nil
            || probed.capabilities?.supports(.contrast) == true
        self.volumeMax = probed.volumeMax
        self.volumeSupported = probed.volume != nil
            || probed.capabilities?.supports(.speakerVolume) == true
        self.muteSupported = probed.muted != nil
            || probed.capabilities?.supports(.audioMute) == true
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
        self.currentInput = probed.inputSource
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
        if busDidFail { return L("Verbindung verloren") }
        if isAirPlay { return L("AirPlay — kein DDC/CI möglich") }
        switch backend {
        case .ddc:
            let base = readConfirmed ? L("DDC/CI verbunden") : L("DDC/CI, keine Rückmeldung")
            // Showing the reported MCCS version makes it visible that the monitor was asked
            // what it can do, rather than assumed.
            if let version = capabilities?.mccsVersion { return "\(base) · MCCS \(version)" }
            return base
        case .builtIn: return L("Internes Display")
        case .software: return L("Softwaredimmung")
        case .unavailable: return L("Nicht steuerbar")
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

    /// Switches the monitor to another input. The picture from this Mac disappears from that
    /// screen until it is switched back — here or at the monitor itself.
    func setInput(_ value: UInt8) {
        guard case .ddc(let link) = backend, inputSources.contains(value) else { return }
        let previous = currentInput
        currentInput = value
        inputSwitchPending = true
        link.schedule(.inputSource, value: UInt16(value))

        // A monitor may simply ignore a switch to an input with nothing plugged into it —
        // measured on an LG UN880, which accepted the command and stayed put. So the claim is
        // checked rather than trusted, and the menu falls back to the truth.
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) { [weak self] in
            guard let self, case .ddc(let link) = self.backend else { return }
            link.read(.inputSource) { result in
                self.inputSwitchPending = false
                guard let result else { self.currentInput = previous; return }
                let actual = UInt8(result.current & 0xFF)
                self.currentInput = actual
                self.inputSwitchRefused = (actual != value)
            }
        }
    }

    /// True while a switch is in flight, and set when the monitor declined it.
    @Published private(set) var inputSwitchPending = false
    @Published var inputSwitchRefused = false

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
    /// The display the volume keys should act on — or nil, which means "leave the keys alone".
    ///
    /// Nil is the common case: as long as macOS can set the current output device's volume
    /// itself, the keys belong to it. Headphones, built-in speakers and audio interfaces all
    /// fall under that. Only a monitor whose audio offers no volume control at all is this
    /// app's business, and then only the monitor the sound is actually going to.
    func displayForVolume() -> ManagedDisplay? {
        guard let output = AudioOutput.current, !output.systemControllable else { return nil }

        let candidates = controllableDisplays.filter(\.volumeSupported)
        guard !candidates.isEmpty else { return nil }

        // CoreAudio names a monitor's audio device after the monitor, which pairs them up.
        if let match = candidates.first(where: { output.matches(displayName: $0.name) }) {
            return match
        }
        // Unambiguous fallback: sound goes to a display, and exactly one can take it.
        if output.isDisplayAttached, candidates.count == 1 {
            return candidates[0]
        }
        // Anything else stays untouched rather than guessing at the wrong device.
        return nil
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
