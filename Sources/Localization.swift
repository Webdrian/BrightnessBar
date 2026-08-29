import Foundation

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
