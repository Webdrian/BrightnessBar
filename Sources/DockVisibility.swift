import AppKit

/// Whether the app also appears in the Dock and app switcher. Off by default: a brightness
/// control belongs in the menu bar. Kept apart from the app entry point so the views that
/// toggle it can be built and rendered without pulling in `@main`.
enum DockVisibility {

    private static let key = "showInDock"

    static var isEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: key) }
        set { UserDefaults.standard.set(newValue, forKey: key) }
    }

    @MainActor
    static func apply() {
        NSApp.setActivationPolicy(isEnabled ? .regular : .accessory)
    }
}
