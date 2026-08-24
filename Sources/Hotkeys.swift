import Foundation
import AppKit
import Carbon.HIToolbox

// MARK: - Global hotkeys
//
// RegisterEventHotKey is used deliberately: unlike a CGEventTap it needs no Accessibility
// permission, so the app works the moment it is launched.

@MainActor
final class HotkeyManager {

    static let shared = HotkeyManager()

    private var handlerRef: EventHandlerRef?
    private var registered: [EventHotKeyRef?] = []
    private var actions: [UInt32: () -> Void] = [:]
    private var nextID: UInt32 = 1

    /// How many shortcuts the system accepted, and how many were refused — a refusal
    /// almost always means another app already owns that combination.
    private(set) var registeredCount = 0
    private(set) var failedCount = 0

    private init() {}

    /// ⌥⌘↑ / ⌥⌘↓ nudge brightness, ⇧⌥⌘↑ / ⇧⌥⌘↓ do it in fine steps.
    func installDefaults(controller: DisplayController) {
        installHandlerIfNeeded()
        let option = UInt32(optionKey), command = UInt32(cmdKey), shift = UInt32(shiftKey)

        register(keyCode: UInt32(kVK_UpArrow), modifiers: option | command) {
            controller.step(percent: 10)
        }
        register(keyCode: UInt32(kVK_DownArrow), modifiers: option | command) {
            controller.step(percent: -10)
        }
        register(keyCode: UInt32(kVK_UpArrow), modifiers: option | command | shift) {
            controller.step(percent: 2)
        }
        register(keyCode: UInt32(kVK_DownArrow), modifiers: option | command | shift) {
            controller.step(percent: -2)
        }
    }

    func unregisterAll() {
        registered.compactMap { $0 }.forEach { UnregisterEventHotKey($0) }
        registered.removeAll()
        actions.removeAll()
        registeredCount = 0
        failedCount = 0
    }

    // MARK: Internals

    private func installHandlerIfNeeded() {
        guard handlerRef == nil else { return }
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))

        InstallEventHandler(GetApplicationEventTarget(), { _, event, _ -> OSStatus in
            var hotKeyID = EventHotKeyID()
            let status = GetEventParameter(
                event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                nil, MemoryLayout<EventHotKeyID>.size, nil, &hotKeyID
            )
            guard status == noErr else { return status }
            let id = hotKeyID.id
            DispatchQueue.main.async { HotkeyManager.shared.fire(id) }
            return noErr
        }, 1, &spec, nil, &handlerRef)
    }

    private func register(keyCode: UInt32, modifiers: UInt32, action: @escaping () -> Void) {
        let id = nextID
        nextID += 1
        var ref: EventHotKeyRef?
        let hotKeyID = EventHotKeyID(signature: OSType(0x42524754), id: id)  // 'BRGT'
        let status = RegisterEventHotKey(keyCode, modifiers, hotKeyID, GetApplicationEventTarget(), 0, &ref)
        guard status == noErr else {
            failedCount += 1
            NSLog("BrightnessBar: Kurzbefehl (keyCode %u) konnte nicht registriert werden, Status %d", keyCode, status)
            return
        }
        actions[id] = action
        registered.append(ref)
        registeredCount += 1
    }

    fileprivate func fire(_ id: UInt32) {
        actions[id]?()
    }
}

// MARK: - Login item
//
// A LaunchAgent rather than SMAppService, because the latter requires a signed bundle and
// this app is built and ad-hoc signed locally.

enum LoginItem {

    private static let label = "de.webdrian.brightnessbar.agent"

    private static var plistURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/LaunchAgents/\(label).plist")
    }

    static var isEnabled: Bool {
        FileManager.default.fileExists(atPath: plistURL.path)
    }

    static func setEnabled(_ enabled: Bool) {
        let url = plistURL
        if enabled {
            guard let executable = Bundle.main.executableURL?.path else { return }
            let plist: [String: Any] = [
                "Label": label,
                "ProgramArguments": [executable],
                "RunAtLoad": true,
                "KeepAlive": false,
                "ProcessType": "Interactive",
            ]
            try? FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(), withIntermediateDirectories: true
            )
            let data = try? PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
            try? data?.write(to: url)
        } else {
            try? FileManager.default.removeItem(at: url)
        }
    }
}
