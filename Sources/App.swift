import SwiftUI
import AppKit

// MARK: - App entry

@main
struct BrightnessBarApp: App {

    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @ObservedObject private var controller = DisplayController.shared

    var body: some Scene {
        MenuBarExtra {
            MenuContent(controller: controller)
        } label: {
            Image(systemName: menuBarSymbol)
        }
        .menuBarExtraStyle(.window)
    }

    /// The icon tracks the brightest controllable display, so the menu bar shows state at a glance.
    private var menuBarSymbol: String {
        let level = controller.controllableDisplays.map(\.brightnessPercent).max() ?? 100
        switch level {
        case ..<20: return "sun.min"
        case ..<60: return "sun.max"
        default: return "sun.max.fill"
        }
    }
}

// MARK: - Delegate

final class AppDelegate: NSObject, NSApplicationDelegate {

    func applicationDidFinishLaunching(_ notification: Notification) {
        DockVisibility.apply()
        buildMainMenu()
        HotkeyManager.shared.installDefaults(controller: DisplayController.shared)
        MediaKeyTap.shared.configure(controller: DisplayController.shared)
    }

    /// A gamma table outlives the process that set it, so it has to be handed back.
    func applicationWillTerminate(_ notification: Notification) {
        SoftwareDimmer.restoreAll()
    }

    /// Clicking the Dock icon has to do something visible, or the app looks broken.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        AboutWindowController.shared.show()
        return true
    }

    // MARK: Menu bar
    //
    // Even without a Dock icon this is worth building: it is what makes ⌘Q and ⌘W work while
    // the About window has focus, and it is where the standard Services and Edit items live.

    @MainActor
    private func buildMainMenu() {
        let mainMenu = NSMenu()

        let appItem = NSMenuItem()
        let appMenu = NSMenu()
        appMenu.addItem(
            withTitle: "Über \(AppInfo.name)",
            action: #selector(showAbout),
            keyEquivalent: ""
        ).target = self
        appMenu.addItem(.separator())
        appMenu.addItem(
            withTitle: "\(AppInfo.name) ausblenden",
            action: #selector(NSApplication.hide(_:)),
            keyEquivalent: "h"
        )
        appMenu.addItem(.separator())
        appMenu.addItem(
            withTitle: "\(AppInfo.name) beenden",
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        )
        appItem.submenu = appMenu
        mainMenu.addItem(appItem)

        let editItem = NSMenuItem()
        let editMenu = NSMenu(title: "Bearbeiten")
        editMenu.addItem(withTitle: "Kopieren", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "Alles auswählen", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editItem.submenu = editMenu
        mainMenu.addItem(editItem)

        let windowItem = NSMenuItem()
        let windowMenu = NSMenu(title: "Fenster")
        windowMenu.addItem(withTitle: "Schließen", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        windowItem.submenu = windowMenu
        mainMenu.addItem(windowItem)
        NSApp.windowsMenu = windowMenu

        NSApp.mainMenu = mainMenu
    }

    @MainActor
    @objc private func showAbout() {
        AboutWindowController.shared.show()
    }
}
