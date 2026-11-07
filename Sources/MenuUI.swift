import SwiftUI
import AppKit

// MARK: - Shared look

enum Theme {
    /// Fixed on purpose: this amber means "attention", not "accent". It keeps its meaning
    /// even when the user repaints the accent colour.
    static let warning = Color(red: 0.98, green: 0.68, blue: 0.13)
    static let ok = Color(red: 0.30, green: 0.80, blue: 0.36)
    static let bad = Color(red: 0.85, green: 0.30, blue: 0.28)

    static let width: CGFloat = 340
    static let cardRadius: CGFloat = 13
    static let labelWidth: CGFloat = 84

    /// Icon and value text inside the bar sliders. A fixed grey, because it sits on the white
    /// fill as often as on the empty track — `.secondary` would vanish on white in dark mode.
    static let barInk = Color(white: 0.45)
}

extension ManagedDisplay.Health {
    var color: Color {
        switch self {
        case .good: return Theme.ok
        case .partial: return Theme.warning
        case .none: return Theme.bad
        }
    }
}

// MARK: - Card

/// The frosted panel every group of controls sits on.
struct CardBackground: ViewModifier {

    @Environment(\.colorScheme) private var scheme

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous)
        content
            .background(shape.fill(scheme == .dark ? Color.white.opacity(0.07) : Color.white.opacity(0.55)))
            .overlay(shape.strokeBorder(Color.white.opacity(scheme == .dark ? 0.08 : 0.7), lineWidth: 0.5))
            .shadow(color: .black.opacity(scheme == .dark ? 0 : 0.04), radius: 2, y: 1)
    }
}

extension View {
    func card() -> some View { modifier(CardBackground()) }
}

struct Card<Content: View>: View {

    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10, content: content)
            .padding(.horizontal, 12)
            .padding(.vertical, 11)
            .frame(maxWidth: .infinity, alignment: .leading)
            .card()
    }
}

// MARK: - Menu content

struct MenuContent: View {

    @ObservedObject var controller: DisplayController
    @ObservedObject private var appearance = Appearance.shared
    @State private var mediaKeysActive = MediaKeyTap.shared.isRunning

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if controller.displays.isEmpty {
                emptyState
            } else if let display = controller.selectedDisplay {
                DisplayHeader(display: display, controller: controller)
                DisplayControls(display: display, controller: controller)
            }

            if controller.controllableDisplays.count > 1 {
                linkCard
            }

            if MediaKeyTap.isEnabled, !mediaKeysActive {
                Button {
                    MediaKeyTap.openAccessibilitySettings()
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 13))
                        Text("Tastenfreigabe fehlt")
                            .font(.system(size: 12))
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.system(size: 10, weight: .semibold))
                    }
                    .foregroundStyle(Theme.warning)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .contentShape(Rectangle())
                    .card()
                }
                .buttonStyle(.plain)
            }

            HStack(spacing: 8) {
                Tile(icon: "gearshape", title: "Einstellungen") {
                    SettingsWindowController.shared.show()
                }
                Tile(icon: "info.circle", title: "Info") {
                    AboutWindowController.shared.show()
                }
                Tile(icon: "power", title: "Beenden") {
                    NSApp.terminate(nil)
                }
            }
        }
        .padding(10)
        .frame(width: Theme.width)
        .onAppear {
            // The permission is often granted while the app is already running.
            mediaKeysActive = MediaKeyTap.shared.refresh()
        }
    }

    private var emptyState: some View {
        Card {
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text(L(controller.isScanning ? "Displays werden gesucht …" : "Kein Display gefunden"))
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
        }
    }

    /// Wide tile like the screenshot's ICCsync: a round icon that fills with the accent
    /// colour while the monitors are linked.
    private var linkCard: some View {
        Button {
            controller.linkAll.toggle()
        } label: {
            HStack(spacing: 12) {
                TileIcon(icon: "link", isActive: controller.linkAll, size: 34)
                VStack(alignment: .leading, spacing: 1) {
                    Text("Monitore koppeln")
                        .font(.system(size: 13, weight: .medium))
                    Text(verbatim: controller.linkAll ? L("Ein") : L("Aus"))
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Toggle("", isOn: $controller.linkAll)
                    .toggleStyle(.switch)
                    .controlSize(.mini)
                    .labelsHidden()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .contentShape(Rectangle())
            .card()
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Header

/// Accent-coloured bar with the display name. With more than one display the right-hand
/// part opens the monitor list.
struct DisplayHeader: View {

    @ObservedObject var display: ManagedDisplay
    @ObservedObject var controller: DisplayController
    @ObservedObject private var appearance = Appearance.shared

    var body: some View {
        HStack(spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "display")
                    .font(.system(size: 18, weight: .regular))

                VStack(alignment: .leading, spacing: 1) {
                    Text(display.displayLabel)
                        .font(.system(size: 14, weight: .semibold))
                        .lineLimit(1)
                    Text(display.statusText)
                        .font(.system(size: 11))
                        .opacity(0.8)
                        .lineLimit(1)
                }

                Spacer(minLength: 6)

                Circle()
                    .fill(display.health.color)
                    .frame(width: 8, height: 8)
                    .overlay(Circle().strokeBorder(Color.white.opacity(0.9), lineWidth: 1.5).padding(-1.5))
                    .padding(.trailing, 12)
            }
            .padding(.leading, 14)

            if controller.displays.count > 1 {
                Rectangle()
                    .fill(Color.white.opacity(0.35))
                    .frame(width: 1)

                Menu {
                    ForEach(controller.displays) { item in
                        Button {
                            controller.selectedDisplayID = item.id
                        } label: {
                            let title = monitorTitle(item)
                            if item.id == display.id {
                                Label(title, systemImage: "checkmark")
                            } else {
                                Text(verbatim: title)
                            }
                        }
                    }
                } label: {
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.system(size: 12, weight: .semibold))
                        .frame(width: 46, height: 52)
                        .contentShape(Rectangle())
                }
                .menuStyle(.button)
                .buttonStyle(.plain)
                .menuIndicator(.hidden)
                .fixedSize()
                .help(L("Monitor auswählen"))
            }
        }
        .foregroundStyle(.white)
        .frame(height: 52)
        .background(
            RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous)
                .fill(appearance.accent)
        )
    }

    private func monitorTitle(_ item: ManagedDisplay) -> String {
        if item.isAirPlay { return "\(item.displayLabel) · AirPlay" }
        if item.isSoftwareDimmed { return "\(item.displayLabel) · \(L("Softwaredimmung"))" }
        return item.displayLabel
    }
}

// MARK: - Controls for one display

struct DisplayControls: View {

    @ObservedObject var display: ManagedDisplay
    @ObservedObject var controller: DisplayController

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if display.isControllable {
                pictureCard

                if display.volumeSupported {
                    soundCard
                }

                if !display.inputSources.isEmpty {
                    inputCard
                }
            } else if display.isAirPlay {
                Card {
                    hint("AirPlay überträgt nur das Bild — einen Steuerkanal zum Gerät gibt es dabei nicht. Helligkeit lässt sich hier nur am Fernseher selbst einstellen.", size: 11)
                }
            } else {
                Card {
                    hint("Dieser Anschluss leitet DDC/CI nicht durch. Adapter und Hubs zwischen Mac und Monitor sind die übliche Ursache — eine direkte DisplayPort- oder USB-C-Verbindung hilft.", size: 11)
                }
            }
        }
    }

    private var pictureCard: some View {
        Card {
            SliderRow(
                title: "Helligkeit",
                icon: "sun.max.fill",
                text: "\(display.brightnessPercent) %",
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
                range: 0...Double(display.brightnessMax),
                trailing: controller.linkAll && controller.controllableDisplays.count > 1 ? "link" : nil
            )

            if display.contrastSupported {
                SliderRow(
                    title: "Kontrast",
                    icon: "circle.righthalf.filled",
                    text: "\(display.contrastPercent) %",
                    value: Binding(
                        get: { display.contrast },
                        set: { display.contrast = $0; display.applyContrast() }
                    ),
                    range: 0...Double(display.contrastMax)
                )
            }

            if display.isSoftwareDimmed {
                hint("Der Regler dunkelt das Bild ab. Das Backlight bleibt unverändert, weil dieser Anschluss DDC/CI nicht durchleitet.")
            }
        }
    }

    private var soundCard: some View {
        Card {
            SliderRow(
                title: "Lautstärke",
                icon: display.isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill",
                text: display.isMuted ? "stumm" : "\(display.volumePercent) %",
                value: Binding(
                    get: { display.volume },
                    set: { display.volume = $0; display.applyVolume() }
                ),
                range: 0...Double(display.volumeMax),
                disabled: display.isMuted
            )

            if display.muteSupported {
                HStack {
                    Text("Stumm")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Toggle("", isOn: Binding(
                        get: { display.isMuted },
                        set: { display.setMuted($0) }
                    ))
                    .toggleStyle(.switch)
                    .controlSize(.mini)
                    .labelsHidden()
                }
            }
        }
    }

    private var inputCard: some View {
        Card {
            HStack {
                Text("Eingang")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                Spacer()
                Menu {
                    ForEach(display.inputSources, id: \.self) { value in
                        Button {
                            confirmInputSwitch(display: display, to: value)
                        } label: {
                            if value == display.currentInput {
                                Label(InputSource.name(for: value), systemImage: "checkmark")
                            } else {
                                Text(InputSource.name(for: value))
                            }
                        }
                    }
                } label: {
                    HStack(spacing: 5) {
                        Text(display.currentInput.map { InputSource.name(for: $0) } ?? L("wählen …"))
                            .font(.system(size: 13, weight: .medium))
                        Image(systemName: "chevron.up.chevron.down")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(.secondary)
                    }
                    .contentShape(Rectangle())
                }
                .menuStyle(.button)
                .buttonStyle(.plain)
                .menuIndicator(.hidden)
                .fixedSize()
                .disabled(display.inputSwitchPending)
            }

            if display.inputSwitchRefused {
                Text("Der Monitor ist beim bisherigen Eingang geblieben. Das tun viele Geräte, wenn an der gewählten Buchse kein Signal anliegt.")
                    .font(.system(size: 10))
                    .foregroundStyle(Theme.warning)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                hint("Schaltet den Monitor auf eine andere Quelle. Das Bild dieses Macs verschwindet dann von diesem Bildschirm — zurück geht es hier oder am Monitor selbst.")
            }
        }
    }

    private func hint(_ text: LocalizedStringKey, size: CGFloat = 10) -> some View {
        Text(text)
            .font(.system(size: size))
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }
}

/// Switching a monitor to another source is easy to do by accident and, on many monitors,
/// impossible to undo from here: they answer DDC only for the input they are currently
/// showing. Measured on an LG UN880 — once it shows the console, the Mac cannot reach it.
/// So the step gets a deliberate confirmation.
@MainActor
private func confirmInputSwitch(display: ManagedDisplay, to value: UInt8) {
    guard value != display.currentInput else { return }

    let alert = NSAlert()
    alert.alertStyle = .warning
    alert.messageText = L("%@ auf %@ umschalten?", display.displayLabel, InputSource.name(for: value))
    alert.informativeText = L("Dieser Bildschirm zeigt danach die andere Quelle, und das Bild dieses Macs verschwindet von ihm. Zurück geht es meist nur am Monitor selbst, weil viele Geräte über den inaktiven Eingang nicht mehr ansprechbar sind.")
    alert.addButton(withTitle: L("Umschalten"))
    alert.addButton(withTitle: L("Abbrechen"))

    NSApp.activate(ignoringOtherApps: true)
    if alert.runModal() == .alertFirstButtonReturn {
        display.setInput(value)
    }
}

/// Label on the left, bar on the right — one line per control, as in the screenshot.
struct SliderRow: View {

    let title: String
    let icon: String
    let text: String
    let value: Binding<Double>
    let range: ClosedRange<Double>
    var disabled: Bool = false
    /// Optional symbol after the bar, e.g. the link mark while the monitors are coupled.
    var trailing: String? = nil

    @ObservedObject private var appearance = Appearance.shared

    var body: some View {
        HStack(spacing: 8) {
            Text(L(title))
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .frame(width: Theme.labelWidth, alignment: .leading)

            BarSlider(value: value, range: range, icon: icon, text: L(text), isEnabled: !disabled)

            if let trailing {
                Image(systemName: trailing)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(appearance.accent)
                    .frame(width: 14)
            }
        }
    }
}

// MARK: - Bar slider
//
// Hand-drawn: a fat capsule whose white fill is the value, with the symbol riding at its left
// end and the number at the right end of the track. No knob — the whole bar is the handle.

struct BarSlider: View {

    let value: Binding<Double>
    let range: ClosedRange<Double>
    let icon: String
    var text: String? = nil
    var isEnabled: Bool = true

    @Environment(\.colorScheme) private var scheme

    private let height: CGFloat = 24

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            // The fill never gets narrower than a circle, so the symbol always sits on white.
            let fillWidth = height + (width - height) * fraction

            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.primary.opacity(scheme == .dark ? 0.14 : 0.08))

                Capsule()
                    .fill(Color.white)
                    .frame(width: fillWidth)
                    .shadow(color: .black.opacity(0.12), radius: 1.5, x: 0.5, y: 0.5)

                Image(systemName: icon)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Theme.barInk)
                    .frame(width: height, height: height)

                if let text {
                    Text(verbatim: text)
                        .font(.system(size: 10))
                        .monospacedDigit()
                        // A shade lighter on the dark track; still readable once the white fill reaches it.
                        .foregroundStyle(scheme == .dark ? Color(white: 0.62) : Theme.barInk)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                        .padding(.trailing, 9)
                }
            }
            .contentShape(Capsule())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { drag in
                        guard isEnabled else { return }
                        let travel = max(width - height, 1)
                        set(fraction: (drag.location.x - height / 2) / travel)
                    }
            )
        }
        .frame(height: height)
        .opacity(isEnabled ? 1 : 0.5)
        .animation(.easeOut(duration: 0.08), value: fraction)
    }

    private var fraction: Double {
        let span = range.upperBound - range.lowerBound
        guard span > 0 else { return 0 }
        return min(1, max(0, (value.wrappedValue - range.lowerBound) / span))
    }

    private func set(fraction: Double) {
        let clamped = min(1, max(0, fraction))
        value.wrappedValue = range.lowerBound + clamped * (range.upperBound - range.lowerBound)
    }
}

// MARK: - Tiles

struct TileIcon: View {

    let icon: String
    var isActive: Bool = false
    var size: CGFloat = 32

    @ObservedObject private var appearance = Appearance.shared

    var body: some View {
        ZStack {
            Circle()
                .fill(isActive ? appearance.accent : Color.primary.opacity(0.08))
            Image(systemName: icon)
                .font(.system(size: size * 0.42, weight: .medium))
                .foregroundStyle(isActive ? Color.white : Color.primary.opacity(0.75))
        }
        .frame(width: size, height: size)
    }
}

struct Tile: View {

    let icon: String
    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                TileIcon(icon: icon)
                Text(L(title))
                    .font(.system(size: 11))
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .contentShape(Rectangle())
            .card()
        }
        .buttonStyle(.plain)
    }
}
