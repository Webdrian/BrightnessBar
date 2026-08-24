import SwiftUI
import AppKit

// MARK: - Menu content

struct MenuContent: View {

    @ObservedObject var controller: DisplayController
    @State private var showContrast = UserDefaults.standard.bool(forKey: "showContrast")
    @State private var launchAtLogin = LoginItem.isEnabled
    @State private var showInDock = DockVisibility.isEnabled

    private var controllable: [ManagedDisplay] { controller.controllableDisplays }
    private var unavailable: [ManagedDisplay] { controller.displays.filter { !$0.isControllable } }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header

            if controller.isScanning && controller.displays.isEmpty {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("Displays werden gesucht …").foregroundStyle(.secondary)
                }
                .padding(.vertical, 6)
            }

            if controllable.count > 1 {
                Toggle("Alle Displays koppeln", isOn: $controller.linkAll)
                    .toggleStyle(.switch)
                    .controlSize(.small)
            }

            ForEach(controllable) { display in
                DisplayRow(display: display, showContrast: showContrast, controller: controller)
            }

            if !unavailable.isEmpty {
                Divider()
                VStack(alignment: .leading, spacing: 3) {
                    Text("Nicht steuerbar")
                        .font(.system(size: 12, weight: .medium))
                    ForEach(unavailable) { display in
                        Text(display.displayLabel)
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                    // One shared explanation: the cause is the same for every display here.
                    Text("Dieser Anschluss leitet DDC/CI nicht durch. Adapter und Hubs zwischen Mac und Monitor sind die übliche Ursache — eine direkte DisplayPort- oder USB-C-Verbindung hilft. Sonst DDC/CI im Monitor-Menü aktivieren.")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 2)
                }
            }

            Divider()
            footer
        }
        .padding(14)
        .frame(width: 320)
    }

    private var header: some View {
        HStack {
            Text("Helligkeit").font(.system(size: 13, weight: .semibold))
            Spacer()
            Button {
                controller.rescan()
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .buttonStyle(.borderless)
            .help("Displays neu einlesen")
            .disabled(controller.isScanning)
        }
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 8) {
            Toggle("Softwaredimmung, wo DDC fehlt", isOn: $controller.softwareDimming)
                .toggleStyle(.switch)
                .controlSize(.small)
                .help("Für Monitore ohne erreichbaren DDC-Kanal: dunkelt das Bild per Gamma-Kurve ab, statt das Backlight zu regeln.")

            Toggle("Kontrast anzeigen", isOn: $showContrast)
                .toggleStyle(.switch)
                .controlSize(.small)
                .onChange(of: showContrast) { _, newValue in
                    UserDefaults.standard.set(newValue, forKey: "showContrast")
                }

            Toggle("Beim Anmelden starten", isOn: $launchAtLogin)
                .toggleStyle(.switch)
                .controlSize(.small)
                .onChange(of: launchAtLogin) { _, newValue in
                    LoginItem.setEnabled(newValue)
                }

            Toggle("Im Dock anzeigen", isOn: $showInDock)
                .toggleStyle(.switch)
                .controlSize(.small)
                .onChange(of: showInDock) { _, newValue in
                    DockVisibility.isEnabled = newValue
                    DockVisibility.apply()
                }

            Text("⌥⌘↑ / ⌥⌘↓ heller bzw. dunkler  ·  mit ⇧ in 2-%-Schritten")
                .font(.system(size: 10))
                .foregroundStyle(.secondary)

            HStack {
                Button("Info") { AboutWindowController.shared.show() }
                    .buttonStyle(.borderless)
                    .font(.system(size: 11))
                Spacer()
                Button("Beenden") { NSApp.terminate(nil) }
                    .buttonStyle(.borderless)
                    .font(.system(size: 11))
            }
        }
    }
}

// MARK: - One display's controls

struct DisplayRow: View {

    @ObservedObject var display: ManagedDisplay
    let showContrast: Bool
    @ObservedObject var controller: DisplayController

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Text(display.displayLabel)
                    .font(.system(size: 12, weight: .medium))
                    .lineLimit(1)
                if !display.readConfirmed, !display.isSoftwareDimmed {
                    Image(systemName: "questionmark.circle")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                        .help("Der Monitor beantwortet keine DDC-Leseanfragen. Der angezeigte Wert ist der letzte gesetzte, Steuern funktioniert trotzdem.")
                }
                Spacer()
                Text("\(display.brightnessPercent) %")
                    .font(.system(size: 11, design: .rounded))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }

            if display.isSoftwareDimmed {
                Text("Softwaredimmung — dunkelt das Bild ab, das Backlight bleibt unverändert.")
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else if !display.readConfirmed {
                Text("Keine DDC-Antwort — Schieben kann trotzdem funktionieren.")
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            slider(
                icon: "sun.max",
                value: Binding(
                    get: { display.brightness },
                    set: { newValue in
                        display.brightness = newValue
                        display.applyBrightness()
                        if controller.linkAll {
                            let percent = display.brightness / Double(display.brightnessMax) * 100
                            for other in controller.controllableDisplays where other.id != display.id {
                                other.setPercent(percent)
                            }
                        }
                    }
                ),
                range: 0...Double(display.brightnessMax)
            )

            if display.volumeSupported {
                HStack(spacing: 6) {
                    Text("Lautstärke").font(.system(size: 10)).foregroundStyle(.secondary)
                    Spacer()
                    Text(display.isMuted ? "stumm" : "\(display.volumePercent) %")
                        .font(.system(size: 10, design: .rounded))
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
                HStack(spacing: 8) {
                    if display.muteSupported {
                        Button {
                            display.setMuted(!display.isMuted)
                        } label: {
                            Image(systemName: display.isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                                .font(.system(size: 10))
                                .frame(width: 12)
                        }
                        .buttonStyle(.borderless)
                        .help(display.isMuted ? "Ton einschalten" : "Stummschalten")
                    } else {
                        Image(systemName: "speaker.wave.2.fill")
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                            .frame(width: 12)
                    }
                    Slider(
                        value: Binding(
                            get: { display.volume },
                            set: { display.volume = $0; display.applyVolume() }
                        ),
                        in: 0...Double(display.volumeMax)
                    )
                    .disabled(display.isMuted)
                }
            }

            if showContrast, display.contrastSupported {
                HStack(spacing: 6) {
                    Text("Kontrast").font(.system(size: 10)).foregroundStyle(.secondary)
                    Spacer()
                    Text("\(display.contrastPercent) %")
                        .font(.system(size: 10, design: .rounded))
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
                slider(
                    icon: "circle.lefthalf.filled",
                    value: Binding(
                        get: { display.contrast },
                        set: { display.contrast = $0; display.applyContrast() }
                    ),
                    range: 0...Double(display.contrastMax)
                )
            }
        }
    }

    private func slider(icon: String, value: Binding<Double>, range: ClosedRange<Double>) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
            Slider(value: value, in: range)
        }
    }
}
