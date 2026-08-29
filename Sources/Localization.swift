import Foundation
import AppKit

// MARK: - Localisation
//
// The interface is German by default; English is available as an alternative and follows the
// system language. SwiftUI localises `Text("…")` and friends on its own once the bundle carries
// the string tables, so only strings built outside SwiftUI go through this helper — window and
// menu titles, alert text, and the labels the display model produces.
//
// The German wording doubles as the key. That keeps the source readable and means a missing
// English entry degrades to correct German rather than to a naked identifier.

/// Looks up a user-facing string. The key is the German text.
func L(_ key: String) -> String {
    NSLocalizedString(key, comment: "")
}

/// Same, with format arguments applied afterwards.
func L(_ key: String, _ arguments: CVarArg...) -> String {
    String(format: NSLocalizedString(key, comment: ""), arguments: arguments)
}

// MARK: - Choosing the language in the app

/// macOS can already set a language per application, but that switch lives in System Settings
/// under Language & Region, where nobody goes looking for it. This writes the very same
/// preference — `AppleLanguages` in the app's own domain — from a place people will find.
enum AppLanguage: String, CaseIterable {

    case system
    case german = "de"
    case english = "en"

    private static let key = "AppleLanguages"

    /// The language names stay in their own language: someone who set English by accident has
    /// to be able to find their way back.
    var label: String {
        switch self {
        case .system: return L("Systemsprache")
        case .german: return "Deutsch"
        case .english: return "English"
        }
    }

    /// Only the app's own domain counts. `UserDefaults.standard` reads through to the global
    /// domain, where `AppleLanguages` always holds the system list — asking it would report a
    /// choice the user never made.
    static var current: AppLanguage {
        guard let identifier = Bundle.main.bundleIdentifier,
              let domain = UserDefaults.standard.persistentDomain(forName: identifier),
              let stored = (domain[key] as? [String])?.first
        else { return .system }
        return AppLanguage(rawValue: String(stored.prefix(2))) ?? .system
    }

    static func select(_ language: AppLanguage) {
        if language == .system {
            UserDefaults.standard.removeObject(forKey: key)
        } else {
            UserDefaults.standard.set([language.rawValue], forKey: key)
        }
    }

    /// The bundle resolves its language once at launch, so the change needs a fresh process.
    @MainActor
    static func restartApp() {
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.createsNewApplicationInstance = true
        NSWorkspace.shared.openApplication(at: Bundle.main.bundleURL, configuration: configuration) { _, _ in
            DispatchQueue.main.async { NSApp.terminate(nil) }
        }
    }
}
