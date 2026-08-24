import Foundation
import CoreGraphics

// MARK: - Software dimming fallback
//
// For displays whose DDC channel is not reachable, the backlight cannot be touched. What is
// still possible is scaling the display's transfer function, which darkens the image itself.
// This is not the same thing as lowering brightness: the backlight keeps burning at full
// power, so nothing is saved and very dark settings cost colour precision. It is the only
// option left when an adapter or hub swallows DDC, so the menu offers it — clearly labelled.

enum SoftwareDimmer {

    /// Never scale all the way to black; a display the user cannot see is a display the user
    /// cannot fix. 0 % still leaves a readable image.
    private static let floor: Double = 0.15

    static let defaultsKey = "softwareDimmingEnabled"

    /// On by default: without it, a display behind such an adapter has no control at all.
    static var isEnabled: Bool {
        get {
            if UserDefaults.standard.object(forKey: defaultsKey) == nil { return true }
            return UserDefaults.standard.bool(forKey: defaultsKey)
        }
        set { UserDefaults.standard.set(newValue, forKey: defaultsKey) }
    }

    private static var dimmed: Set<CGDirectDisplayID> = []

    @discardableResult
    static func apply(_ displayID: CGDirectDisplayID, percent: Double) -> Bool {
        let clamped = max(0, min(100, percent)) / 100
        let scale = Float(floor + (1 - floor) * clamped)

        let result = CGSetDisplayTransferByFormula(
            displayID,
            0, scale, 1,
            0, scale, 1,
            0, scale, 1
        )
        guard result == .success else { return false }
        if scale >= 0.999 {
            dimmed.remove(displayID)
        } else {
            dimmed.insert(displayID)
        }
        return true
    }

    /// Returns one display to its untouched transfer function.
    static func restore(_ displayID: CGDirectDisplayID) {
        CGSetDisplayTransferByFormula(displayID, 0, 1, 1, 0, 1, 1, 0, 1, 1)
        dimmed.remove(displayID)
    }

    /// Must run before the app goes away — a gamma table set by a dead process would
    /// otherwise stay in place until the user logs out.
    static func restoreAll() {
        for displayID in dimmed {
            CGSetDisplayTransferByFormula(displayID, 0, 1, 1, 0, 1, 1, 0, 1, 1)
        }
        dimmed.removeAll()
        CGDisplayRestoreColorSyncSettings()
    }
}
