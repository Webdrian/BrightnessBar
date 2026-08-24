import SwiftUI
import AppKit

// MARK: - Shared look

enum Theme {
    /// Fixed on purpose: this amber means "attention", not "accent". It keeps its meaning
    /// even when the user repaints the accent colour.
    static let warning = Color(red: 0.98, green: 0.68, blue: 0.13)
    static let ok = Color(red: 0.30, green: 0.80, blue: 0.36)
    static let bad = Color(red: 0.85, green: 0.30, blue: 0.28)

    static let rowIconWidth: CGFloat = 22
    static let width: CGFloat = 320
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

// MARK: - Menu content

struct MenuContent: View {

    @ObservedObject var controller: DisplayController
    @State private var mediaKeysActive = MediaKeyTap.shared.isRunning

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if controller.displays.isEmpty {
                emptyState
            } else if let display = controller.selectedDisplay {
                DisplayHeader(display: display)
                    .padding(.horizontal, 16)
                    .padding(.top, 14)
                    .padding(.bottom, 12)

                separator

                DisplayControls(display: display, controller: controller)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)

                if controller.displays.count > 1 {
                    separator
                    monitorPicker
                        .padding(.horizontal, 8)
                        .padding(.vertical, 8)
                }
            }

            separator
            actions
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
        }
        .frame(width: Theme.width)
        .onAppear {
            // The permission is often granted while the app is already running.
            mediaKeysActive = MediaKeyTap.shared.refresh()
        }
    }

    private var separator: some View {
        Rectangle()
            .fill(Color.primary.opacity(0.10))
            .frame(height: 1)
            .padding(.horizontal, 16)
    }

    private var emptyState: some View {
        HStack(spacing: 8) {
            ProgressView().controlSize(.small)
            Text(controller.isScanning ? "Displays werden gesucht …" : "Kein Display gefunden")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
        }
        .padding(16)
    }

    // MARK: Monitor picker

    private var monitorPicker: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Monitor auswählen")
                .font(.system(size: 10, weight: .semibold))
                .kerning(0.6)
                .textCase(.uppercase)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 8)
                .padding(.bottom, 4)

            ForEach(controller.displays) { display in
                MonitorRow(
                    display: display,
                    isSelected: display.id == controller.selectedDisplay?.id,
                    action: { controller.selectedDisplayID = display.id }
                )
            }
        }
    }

    // MARK: Bottom actions

    private var actions: some View {
        VStack(spacing: 1) {
            if controller.controllableDisplays.count > 1 {
                ActionRow(icon: "link", title: "Monitore koppeln") {
                    Toggle("", isOn: $controller.linkAll)
                        .toggleStyle(.switch)
                        .controlSize(.mini)
                        .labelsHidden()
                }
            }

            if MediaKeyTap.isEnabled, !mediaKeysActive {
                ActionRow(icon: "exclamationmark.triangle", title: "Tastenfreigabe fehlt", tint: Theme.warning) {
                    EmptyView()
                }
                .onTapGesture { MediaKeyTap.openAccessibilitySettings() }
            }

            ActionRow(icon: "gearshape", title: "Einstellungen …", showsChevron: true) { EmptyView() }
                .onTapGesture { SettingsWindowController.shared.show() }

            ActionRow(icon: "info.circle", title: "Info") { EmptyView() }
                .onTapGesture { AboutWindowController.shared.show() }

            ActionRow(icon: "power", title: "BrightnessBar beenden") { EmptyView() }
                .onTapGesture { NSApp.terminate(nil) }
        }
    }
}

// MARK: - Header

struct DisplayHeader: View {

    @ObservedObject var display: ManagedDisplay

    var body: some View {
        HStack(spacing: 11) {
            Image(systemName: "display")
                .font(.system(size: 26, weight: .light))
                .frame(width: 34)

            VStack(alignment: .leading, spacing: 1) {
                Text(display.displayLabel)
                    .font(.system(size: 14, weight: .semibold))
                    .lineLimit(1)
                Text(display.statusText)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 6)

            Circle()
                .fill(display.health.color)
                .frame(width: 8, height: 8)
        }
    }
}

// MARK: - Sliders for one display

struct DisplayControls: View {

    @ObservedObject var display: ManagedDisplay
    @ObservedObject var controller: DisplayController

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if display.isControllable {
                ValueSlider(
                    title: "Helligkeit",
                    icon: "sun.max",
                    percent: display.brightnessPercent,
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

                if display.contrastSupported {
                    ValueSlider(
                        title: "Kontrast",
                        icon: "circle.righthalf.filled",
                        percent: display.contrastPercent,
                        value: Binding(
                            get: { display.contrast },
                            set: { display.contrast = $0; display.applyContrast() }
                        ),
                        range: 0...Double(display.contrastMax)
                    )
                }

                if display.volumeSupported {
                    // The mockup groups picture and sound apart; the hairline does that.
                    Rectangle()
                        .fill(Color.primary.opacity(0.10))
                        .frame(height: 1)
                        .padding(.vertical, 2)

                    ValueSlider(
                        title: "Lautstärke",
                        icon: display.isMuted ? "speaker.slash" : "speaker.wave.2",
                        percent: display.volumePercent,
                        valueLabel: display.isMuted ? "stumm" : nil,
                        value: Binding(
                            get: { display.volume },
                            set: { display.volume = $0; display.applyVolume() }
                        ),
                        range: 0...Double(display.volumeMax),
                        disabled: display.isMuted
                    )

                    if display.muteSupported {
                        HStack {
                            Text("Stumm").font(.system(size: 12))
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

                if display.isSoftwareDimmed {
                    Text("Der Regler dunkelt das Bild ab. Das Backlight bleibt unverändert, weil dieser Anschluss DDC/CI nicht durchleitet.")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            } else {
                Text("Dieser Anschluss leitet DDC/CI nicht durch. Adapter und Hubs zwischen Mac und Monitor sind die übliche Ursache — eine direkte DisplayPort- oder USB-C-Verbindung hilft.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

struct ValueSlider: View {

    let title: String
    let icon: String
    let percent: Int
    var valueLabel: String? = nil
    let value: Binding<Double>
    let range: ClosedRange<Double>
    var disabled: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text(title).font(.system(size: 12))
                Spacer()
                Text(valueLabel ?? "\(percent) %")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .frame(width: 18)
                TintedSlider(value: value, range: range, isEnabled: !disabled)
                    .frame(height: 20)
            }
        }
    }
}

// MARK: - Slider
//
// Hand-drawn rather than wrapped: SwiftUI's Slider ignores `.tint` for the filled track on
// macOS, and NSSlider's `trackFillColor` only paints in an active window. Drawing it directly
// keeps the colour identical everywhere — menu, screenshot, inactive window.

struct TintedSlider: View {

    let value: Binding<Double>
    let range: ClosedRange<Double>
    var isEnabled: Bool = true

    @ObservedObject private var appearance = Appearance.shared

    private let trackHeight: CGFloat = 6
    private let knobSize: CGFloat = 18

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            let travel = max(width - knobSize, 1)
            let fraction = self.fraction
            let knobCenter = knobSize / 2 + travel * fraction

            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.primary.opacity(0.16))
                    .frame(height: trackHeight)

                Capsule()
                    .fill(isEnabled ? appearance.accent : Color.secondary.opacity(0.4))
                    .frame(width: max(knobCenter, trackHeight), height: trackHeight)

                Circle()
                    .fill(Color.white)
                    .frame(width: knobSize, height: knobSize)
                    .shadow(color: .black.opacity(0.25), radius: 1.5, y: 0.5)
                    .offset(x: knobCenter - knobSize / 2)
            }
            .frame(height: knobSize)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { drag in
                        guard isEnabled else { return }
                        let position = (drag.location.x - knobSize / 2) / travel
                        set(fraction: position)
                    }
            )
        }
        .frame(height: knobSize)
        .opacity(isEnabled ? 1 : 0.5)
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

// MARK: - Rows

struct MonitorRow: View {

    @ObservedObject private var appearance = Appearance.shared
    @ObservedObject var display: ManagedDisplay
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: "checkmark")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(appearance.accent)
                    .frame(width: 14)
                    .opacity(isSelected ? 1 : 0)

                VStack(alignment: .leading, spacing: 0) {
                    Text(display.displayLabel)
                        .font(.system(size: 12))
                        .lineLimit(1)
                    if display.isSoftwareDimmed {
                        Text("Softwaredimmung")
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer(minLength: 6)

                Circle()
                    .fill(display.health.color)
                    .frame(width: 7, height: 7)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(isSelected ? Color.primary.opacity(0.10) : Color.clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

struct ActionRow<Accessory: View>: View {

    let icon: String
    let title: String
    var tint: Color? = nil
    var showsChevron: Bool = false
    @ViewBuilder let accessory: () -> Accessory

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 13))
                .foregroundStyle(tint ?? .secondary)
                .frame(width: Theme.rowIconWidth)
            Text(title)
                .font(.system(size: 12))
                .foregroundStyle(tint ?? .primary)
            Spacer(minLength: 6)
            accessory()
            if showsChevron {
                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 7)
        .contentShape(Rectangle())
    }
}
