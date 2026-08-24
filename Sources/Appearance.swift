import SwiftUI
import AppKit

// MARK: - Accent colour
//
// Only the interactive parts follow this: sliders and the selected row. Status colours stay
// fixed, because a green dot that means "works" and an amber one that means "only the image
// is being dimmed" would lose their meaning if the user could repaint them.

@MainActor
final class Appearance: ObservableObject {

    static let shared = Appearance()

    private static let defaultsKey = "accentColor"

    /// Either `system` — follow the macOS accent colour — or a stored hex value.
    @Published var selection: String {
        didSet { UserDefaults.standard.set(selection, forKey: Self.defaultsKey) }
    }

    private init() {
        self.selection = UserDefaults.standard.string(forKey: Self.defaultsKey) ?? Appearance.systemToken
    }

    static let systemToken = "system"

    var accent: Color {
        if selection == Self.systemToken { return Color(nsColor: .controlAccentColor) }
        return Color(hex: selection) ?? Color(nsColor: .controlAccentColor)
    }

    /// Shown in the settings picker, in the order they appear there.
    static let presets: [(name: String, token: String)] = [
        ("Systemfarbe", systemToken),
        ("Blau", "#0A84FF"),
        ("Türkis", "#40C8E0"),
        ("Grün", "#30D158"),
        ("Bernstein", "#FAAD21"),
        ("Orange", "#FF9F0A"),
        ("Rot", "#FF453A"),
        ("Pink", "#FF375F"),
        ("Violett", "#BF5AF2"),
        ("Grafit", "#98989D"),
    ]

    static func color(for token: String) -> Color {
        token == systemToken ? Color(nsColor: .controlAccentColor) : (Color(hex: token) ?? .gray)
    }
}

extension Color {

    /// Accepts "#RRGGBB". Returns nil for anything else, so a corrupted preference falls back
    /// rather than crashing.
    init?(hex: String) {
        var text = hex.trimmingCharacters(in: .whitespaces)
        if text.hasPrefix("#") { text.removeFirst() }
        guard text.count == 6, let value = UInt32(text, radix: 16) else { return nil }
        self.init(
            red: Double((value >> 16) & 0xFF) / 255,
            green: Double((value >> 8) & 0xFF) / 255,
            blue: Double(value & 0xFF) / 255
        )
    }

    var hexString: String {
        let ns = NSColor(self).usingColorSpace(.sRGB) ?? .gray
        return String(format: "#%02X%02X%02X",
                      Int((ns.redComponent * 255).rounded()),
                      Int((ns.greenComponent * 255).rounded()),
                      Int((ns.blueComponent * 255).rounded()))
    }
}
