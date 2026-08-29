import SwiftUI
import AppKit

// MARK: - App metadata

enum AppInfo {

    static var name: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String ?? "BrightnessBar"
    }

    static var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
    }

    static var build: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"
    }

    static let repositoryURL = URL(string: "https://github.com/Webdrian/BrightnessBar")!
    static let websiteURL = URL(string: "https://webdrian.de")!

    /// Read from the bundle rather than hard-coded, so the year lives in one place.
    static var copyright: String {
        Bundle.main.object(forInfoDictionaryKey: "NSHumanReadableCopyright") as? String
            ?? "© 2026 Webdrian"
    }
}

// MARK: - About window

/// A single reused window. Opening the panel twice should raise the existing one rather than
/// stack copies of it.
@MainActor
final class AboutWindowController {

    static let shared = AboutWindowController()

    private var window: NSWindow?

    private init() {}

    func show() {
        if let window {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let hosting = NSHostingController(rootView: AboutView())
        let window = NSWindow(contentViewController: hosting)
        window.title = L("Über %@", AppInfo.name)
        window.styleMask = [.titled, .closable, .fullSizeContentView]
        window.titlebarAppearsTransparent = true
        window.isReleasedWhenClosed = false
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        self.window = window
    }
}

struct AboutView: View {

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 10) {
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .frame(width: 76, height: 76)

                VStack(spacing: 3) {
                    Text(AppInfo.name)
                        .font(.system(size: 17, weight: .semibold))
                    Text(verbatim: L("Version %@ (%@)", AppInfo.version, AppInfo.build))
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }

                Text("Helligkeit externer Monitore aus der Menüleiste — über DDC/CI, das macOS selbst nicht anbietet.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.top, 26)
            .padding(.horizontal, 28)

            Divider().padding(.vertical, 18)

            VStack(alignment: .leading, spacing: 7) {
                Text("Tastenkürzel")
                    .font(.system(size: 11, weight: .semibold))
                shortcut("⌥⌘↑", "heller (10 %)")
                shortcut("⌥⌘↓", "dunkler (10 %)")
                shortcut("⇧⌥⌘↑", "heller (2 %)")
                shortcut("⇧⌥⌘↓", "dunkler (2 %)")
                Text("Wirken auf den Monitor unter dem Mauszeiger.")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .padding(.top, 2)

                Text("Zusätzlich lassen sich die Helligkeits- und Lautstärketasten der Tastatur belegen — im Menü einschaltbar, braucht die Berechtigung „Bedienungshilfen“.")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 28)

            Divider().padding(.vertical, 18)

            VStack(spacing: 7) {
                HStack(spacing: 14) {
                    Link("Projektseite auf GitHub", destination: AppInfo.repositoryURL)
                    Link("webdrian.de", destination: AppInfo.websiteURL)
                }
                .font(.system(size: 11))

                Text(AppInfo.copyright)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                Text("MIT-Lizenz · Quelltext offen")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }
            .padding(.bottom, 24)
        }
        .frame(width: 340)
    }

    private func shortcut(_ keys: String, _ description: String) -> some View {
        HStack(spacing: 10) {
            Text(keys)
                .font(.system(size: 11, design: .monospaced))
                .frame(width: 58, alignment: .leading)
            Text(L(description))
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            Spacer()
        }
    }
}
