import AppKit
import CoreGraphics
import ApplicationServices

// MARK: - Hardware media keys
//
// The brightness and volume keys on the keyboard are not ordinary key presses: they arrive as
// NSSystemDefined events with subtype 8, carrying the key identity packed into `data1`. To see
// them — and to swallow them so macOS does not also react — an event tap is needed, and that
// requires Accessibility permission. Everything else in this app works without permissions, so
// this is deliberately opt-in.

/// Diagnostic output goes to a file: NSLog from this app does not reach the unified log,
/// which makes `log show` useless for troubleshooting it.
enum DiagLog {

    static let url = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Logs/BrightnessBar-diag.log")

    static func write(_ message: String) {
        let line = "\(Date().formatted(date: .omitted, time: .standard))  \(message)\n"
        guard let data = line.data(using: .utf8) else { return }
        if let handle = try? FileHandle(forWritingTo: url) {
            defer { try? handle.close() }
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: data)
        } else {
            try? data.write(to: url)
        }
    }
}

/// F1-F12 — the only ordinary keys the diagnostic mode looks at. Outside the actor-isolated
/// class so the tap callback can read it without hopping.
let functionKeyCodes: Set<UInt16> = [122, 120, 99, 118, 96, 97, 98, 100, 101, 109, 103, 111]

/// Key identities from IOKit's `ev_keymap.h`.
enum MediaKey: Int32 {
    case soundUp = 0
    case soundDown = 1
    case brightnessUp = 2
    case brightnessDown = 3
    case mute = 7
}

/// The three fields packed into a system-defined event's `data1`.
struct MediaKeyEvent {
    let key: MediaKey
    let isKeyDown: Bool
    let isRepeat: Bool

    /// data1 layout: key code in the high 16 bits; in the low 16 bits, the key state in
    /// bits 8-15 (0x0A means pressed) and the auto-repeat flag in bit 0.
    init?(data1: Int) {
        guard let key = MediaKey(rawValue: Int32((data1 & 0xFFFF_0000) >> 16)) else { return nil }
        let flags = data1 & 0x0000_FFFF
        self.key = key
        self.isKeyDown = ((flags & 0xFF00) >> 8) == 0x0A
        self.isRepeat = (flags & 0x1) == 1
    }
}

@MainActor
final class MediaKeyTap {

    static let shared = MediaKeyTap()

    static let defaultsKey = "mediaKeysEnabled"

    private var tap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private weak var controller: DisplayController?

    private init() {}

    /// Opt-in, because switching it on triggers the Accessibility prompt.
    static var isEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: defaultsKey) }
        set { UserDefaults.standard.set(newValue, forKey: defaultsKey) }
    }

    static var hasPermission: Bool { AXIsProcessTrusted() }

    /// Diagnostic logging, switched on with
    /// `defaults write de.webdrian.brightnessbar logMediaKeys -bool true`.
    ///
    /// Deliberately narrow: system-defined media keys are logged by key code, and ordinary
    /// key presses only when they are a function key. Nothing that could reconstruct typed
    /// text is ever recorded.
    static var isLogging: Bool { UserDefaults.standard.bool(forKey: "logMediaKeys") }


    var isRunning: Bool { tap != nil }

    func configure(controller: DisplayController) {
        self.controller = controller
        if Self.isEnabled { _ = start() }
    }

    /// Asks for Accessibility permission, showing the system prompt.
    static func requestPermission() {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        AXIsProcessTrustedWithOptions([key: true] as CFDictionary)
    }

    /// Opens the exact settings pane, because "somewhere under Privacy" is not a useful hint.
    static func openAccessibilitySettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") else { return }
        NSWorkspace.shared.open(url)
    }

    /// Called whenever the menu opens: picks up a permission that was granted while the app
    /// was already running, so no restart is needed. Returns the state to display.
    @discardableResult
    func refresh() -> Bool {
        guard Self.isEnabled else { stop(); return false }
        if !isRunning { _ = start() }
        return isRunning
    }

    /// Returns false when the tap could not be created — almost always missing permission.
    @discardableResult
    func start() -> Bool {
        guard tap == nil else { return true }

        // Bit 14 is NSSystemDefined. In diagnostic mode bit 10 (keyDown) is added, to find out
        // whether a keyboard sends brightness as a media key at all — some do not.
        var mask = CGEventMask(1 << 14)
        if Self.isLogging { mask |= CGEventMask(1 << 10) }
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,          // .defaultTap so events can be swallowed
            eventsOfInterest: mask,
            callback: { _, type, event, _ in mediaKeyTapCallback(type: type, event: event) },
            userInfo: nil
        ) else { return false }

        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)

        self.tap = tap
        self.runLoopSource = source
        return true
    }

    func stop() {
        if let tap { CGEvent.tapEnable(tap: tap, enable: false) }
        if let runLoopSource { CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes) }
        tap = nil
        runLoopSource = nil
    }

    /// macOS disables a tap that blocks for too long; it has to be switched back on.
    func reenable() {
        guard let tap else { return }
        CGEvent.tapEnable(tap: tap, enable: true)
    }

    // MARK: Acting on a key

    /// Returns true when the key was handled and should not reach macOS.
    func handle(_ event: MediaKeyEvent, optionHeld: Bool) -> Bool {
        guard let controller else { return false }

        // ⌥ plus a media key opens the matching settings pane in macOS. Leave that alone.
        guard !optionHeld else { return false }
        guard event.isKeyDown else {
            // Swallow the matching key-up too, so macOS never sees half a press.
            return isHandledKey(event.key, controller: controller)
        }

        switch event.key {
        case .brightnessUp:
            guard !controller.controllableDisplays.isEmpty else { return false }
            controller.step(percent: 6)
            return true
        case .brightnessDown:
            guard !controller.controllableDisplays.isEmpty else { return false }
            controller.step(percent: -6)
            return true
        case .soundUp:
            guard let display = controller.displayForVolume() else { return false }
            display.stepVolume(sixteenths: 1)
            return true
        case .soundDown:
            guard let display = controller.displayForVolume() else { return false }
            display.stepVolume(sixteenths: -1)
            return true
        case .mute:
            guard let display = controller.displayForVolume(), display.muteSupported else { return false }
            display.setMuted(!display.isMuted)
            return true
        }
    }

    private func isHandledKey(_ key: MediaKey, controller: DisplayController) -> Bool {
        switch key {
        case .brightnessUp, .brightnessDown:
            return !controller.controllableDisplays.isEmpty
        case .soundUp, .soundDown, .mute:
            return controller.displayForVolume() != nil
        }
    }
}

// MARK: - Tap callback
//
// A C callback cannot capture context, so it goes through the shared instance. The tap sits on
// the main run loop, so this already runs on the main thread.

private func mediaKeyTapCallback(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
    let passThrough = Unmanaged.passUnretained(event)

    if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
        MainActor.assumeIsolated { MediaKeyTap.shared.reenable() }
        return passThrough
    }

    guard let nsEvent = NSEvent(cgEvent: event) else { return passThrough }

    if MainActor.assumeIsolated({ MediaKeyTap.isLogging }) {
        if nsEvent.type == .keyDown, functionKeyCodes.contains(nsEvent.keyCode) {
            var mods: [String] = []
            if nsEvent.modifierFlags.contains(.command) { mods.append("cmd") }
            if nsEvent.modifierFlags.contains(.option) { mods.append("alt") }
            if nsEvent.modifierFlags.contains(.control) { mods.append("ctrl") }
            if nsEvent.modifierFlags.contains(.shift) { mods.append("shift") }
            if nsEvent.modifierFlags.contains(.function) { mods.append("fn") }
            DiagLog.write("Funktionstaste keyCode=\(nsEvent.keyCode) mods=[\(mods.joined(separator: ","))]")
        } else if nsEvent.type == .systemDefined, nsEvent.subtype.rawValue == 8 {
            let code = (nsEvent.data1 & 0xFFFF_0000) >> 16
            let state = (nsEvent.data1 & 0xFF00) >> 8
            var mods: [String] = []
            if nsEvent.modifierFlags.contains(.command) { mods.append("cmd") }
            if nsEvent.modifierFlags.contains(.option) { mods.append("alt") }
            if nsEvent.modifierFlags.contains(.control) { mods.append("ctrl") }
            if nsEvent.modifierFlags.contains(.shift) { mods.append("shift") }
            if nsEvent.modifierFlags.contains(.function) { mods.append("fn") }
            DiagLog.write("Medientaste code=\(code) state=0x\(String(state, radix: 16)) " +
                          "mods=[\(mods.joined(separator: ","))] " +
                          "raw=0x\(String(nsEvent.modifierFlags.rawValue, radix: 16))")
        }
    }

    // keyDown is only ever observed for diagnostics, never swallowed.
    guard nsEvent.type == .systemDefined,
          nsEvent.subtype.rawValue == 8,
          let mediaKey = MediaKeyEvent(data1: nsEvent.data1)
    else { return passThrough }

    let optionHeld = nsEvent.modifierFlags.contains(.option)
    let handled = MainActor.assumeIsolated {
        MediaKeyTap.shared.handle(mediaKey, optionHeld: optionHeld)
    }
    return handled ? nil : passThrough
}
