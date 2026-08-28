import SwiftUI
import AppKit

// MARK: - Settings window

/// One reused window, like the About panel: opening twice raises the existing one.
@MainActor
final class SettingsWindowController {

    static let shared = SettingsWindowController()

    private var window: NSWindow?

    private init() {}

    func show() {
        if let window {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        let hosting = NSHostingController(rootView: SettingsView(controller: DisplayController.shared))
        let window = NSWindow(contentViewController: hosting)
        window.title = "Einstellungen"
        window.styleMask = [.titled, .closable]
        window.isReleasedWhenClosed = false
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        self.window = window
    }
}

struct SettingsView: View {

    @ObservedObject var controller: DisplayController

    @State private var softwareDimming = SoftwareDimmer.isEnabled
    @State private var mediaKeys = MediaKeyTap.isEnabled
    @State private var mediaKeysActive = MediaKeyTap.shared.isRunning
    @State private var launchAtLogin = LoginItem.isEnabled
    @State private var showInDock = DockVisibility.isEnabled
    @ObservedObject private var appearance = Appearance.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            section("Steuerung") {
                settingToggle(
                    "Softwaredimmung, wo DDC fehlt",
                    "Monitore, deren I²C-Kanal der Mac nicht erreicht, dunkeln über die Gamma-Kurve ab. Das Backlight bleibt dabei unverändert.",
                    isOn: $softwareDimming
                )
                .onChange(of: softwareDimming) { _, newValue in
                    controller.softwareDimming = newValue
                }
            }

            section("Farbe") {
                accentPicker
            }

            section("Tastatur") {
                settingToggle(
                    "Tasten der Tastatur verwenden",
                    "Legt die Helligkeits- und Lautstärketasten auf die Monitore. Die Lautstärketasten greifen nur, wenn der Ton auf einem Monitor liegt, den macOS selbst nicht regeln kann — Kopfhörer und Lautsprecher bleiben unberührt. Braucht die Berechtigung „Bedienungshilfen“.",
                    isOn: $mediaKeys
                )
                .onChange(of: mediaKeys) { _, newValue in
                    MediaKeyTap.isEnabled = newValue
                    if newValue {
                        mediaKeysActive = MediaKeyTap.shared.start()
                        if !mediaKeysActive { MediaKeyTap.requestPermission() }
                    } else {
                        MediaKeyTap.shared.stop()
                        mediaKeysActive = false
                    }
                }

                if mediaKeys {
                    HStack(spacing: 7) {
                        Circle()
                            .fill(mediaKeysActive ? Theme.ok : Theme.warning)
                            .frame(width: 7, height: 7)
                        Text(mediaKeysActive ? "Tasten sind aktiv" : "Berechtigung fehlt")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                        if !mediaKeysActive {
                            Button("Bedienungshilfen öffnen") { MediaKeyTap.openAccessibilitySettings() }
                                .buttonStyle(.link)
                                .font(.system(size: 11))
                        }
                    }
                    .padding(.leading, 2)
                }
            }

            section("Start") {
                settingToggle(
                    "Beim Anmelden starten",
                    "Legt einen LaunchAgent an, der auf den aktuellen Ort der App zeigt.",
                    isOn: $launchAtLogin
                )
                .onChange(of: launchAtLogin) { _, newValue in LoginItem.setEnabled(newValue) }

                settingToggle(
                    "Im Dock anzeigen",
                    "Normalerweise lebt die App nur in der Menüleiste.",
                    isOn: $showInDock
                )
                .onChange(of: showInDock) { _, newValue in
                    DockVisibility.isEnabled = newValue
                    DockVisibility.apply()
                }
            }

            Divider()

            shortcuts
        }
        .padding(24)
        .frame(width: 460)
    }

    private var accentPicker: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 9) {
                ForEach(Appearance.presets, id: \.token) { preset in
                    swatch(token: preset.token, name: preset.name)
                }
            }

            HStack(spacing: 10) {
                ColorPicker("Eigene Farbe", selection: Binding(
                    get: { appearance.accent },
                    set: { appearance.selection = $0.hexString }
                ), supportsOpacity: false)
                .labelsHidden()
                Text("Eigene Farbe …")
                    .font(.system(size: 12))
                Spacer()
                Text(appearance.selection == Appearance.systemToken
                     ? "Folgt der Systemfarbe"
                     : appearance.selection.uppercased())
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.secondary)
            }

            Text("Gilt für die Regler und die Auswahl. Die Statuspunkte behalten ihre Farben — grün, gelb und rot bedeuten dort etwas.")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func swatch(token: String, name: String) -> some View {
        let isSelected = appearance.selection == token
        return Button {
            appearance.selection = token
        } label: {
            ZStack {
                Circle()
                    .fill(Appearance.color(for: token))
                    .frame(width: 20, height: 20)
                if token == Appearance.systemToken {
                    Image(systemName: "sparkles")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.white.opacity(0.9))
                }
                if isSelected {
                    Circle()
                        .stroke(Color.primary.opacity(0.55), lineWidth: 2)
                        .frame(width: 26, height: 26)
                }
            }
            .frame(width: 28, height: 28)
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .help(name)
    }

    // MARK: Pieces

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .kerning(0.6)
                .textCase(.uppercase)
                .foregroundStyle(.secondary)
            content()
        }
    }

    private func settingToggle(_ title: String, _ explanation: String, isOn: Binding<Bool>) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Toggle(title, isOn: isOn)
                .toggleStyle(.switch)
                .controlSize(.small)
                .font(.system(size: 12))
            Text(explanation)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var shortcuts: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Tastenkürzel")
                .font(.system(size: 11, weight: .semibold))
                .kerning(0.6)
                .textCase(.uppercase)
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 7) {
                shortcut("⌥⌘↑", "Heller", "in 10-%-Schritten")
                shortcut("⌥⌘↓", "Dunkler", "in 10-%-Schritten")
                shortcut("⇧⌥⌘↑", "Heller, fein", "in 2-%-Schritten")
                shortcut("⇧⌥⌘↓", "Dunkler, fein", "in 2-%-Schritten")
            }

            Text("Diese vier wirken immer, ohne Zusatzrechte. Sie regeln den Monitor, auf dem der Mauszeiger gerade steht — oder alle zugleich, wenn im Menü *Monitore koppeln* aktiv ist.")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if mediaKeys {
                VStack(alignment: .leading, spacing: 7) {
                    shortcut("F1 / F2", "Helligkeit", "Tasten der Tastatur")
                    shortcut("Lautstärke", "Lautstärke und Stumm", "Tasten der Tastatur")
                }
                .padding(.top, 4)

                Text("Reagiert eine dieser Tasten nicht, erzeugt die Tastatur dafür kein Ereignis — manche Herstellersoftware führt sie selbst aus. Dann hilft es, die Taste dort auf ⌥⌘↑ bzw. ⌥⌘↓ zu legen.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func shortcut(_ keys: String, _ title: String, _ detail: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(keys)
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .background(
                    RoundedRectangle(cornerRadius: 5)
                        .fill(Color.primary.opacity(0.08))
                )
                .frame(width: 96, alignment: .leading)
            Text(title)
                .font(.system(size: 12))
            Text(detail)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            Spacer(minLength: 0)
        }
    }
}
