import Foundation
import CoreGraphics

// MARK: - Built-in / Apple-native panel backend
//
// Internal MacBook panels and Apple-branded Thunderbolt displays are not on an I²C bus
// we can reach; they go through DisplayServices instead. Resolved at runtime because the
// framework is private. Not exercised on a Mac Studio — there is no internal panel here.

private let displayServicesHandle: UnsafeMutableRawPointer? =
    dlopen("/System/Library/PrivateFrameworks/DisplayServices.framework/DisplayServices", RTLD_LAZY)

private typealias GetBrightnessFn = @convention(c) (CGDirectDisplayID, UnsafeMutablePointer<Float>) -> Int32
private typealias SetBrightnessFn = @convention(c) (CGDirectDisplayID, Float) -> Int32

private func dsSym<T>(_ name: String, as type: T.Type) -> T? {
    guard let handle = displayServicesHandle, let p = dlsym(handle, name) else { return nil }
    return unsafeBitCast(p, to: T.self)
}

private let dsGetBrightness = dsSym("DisplayServicesGetBrightness", as: GetBrightnessFn.self)
private let dsSetBrightness = dsSym("DisplayServicesSetBrightness", as: SetBrightnessFn.self)

enum BuiltInBrightness {

    static var isAvailable: Bool { dsGetBrightness != nil && dsSetBrightness != nil }

    /// Current brightness as 0...100, or `nil` if DisplayServices will not answer.
    static func read(_ displayID: CGDirectDisplayID) -> UInt16? {
        guard let get = dsGetBrightness else { return nil }
        var value: Float = 0
        guard get(displayID, &value) == 0, value.isFinite else { return nil }
        return UInt16((max(0, min(1, value)) * 100).rounded())
    }

    @discardableResult
    static func write(_ displayID: CGDirectDisplayID, percent: UInt16) -> Bool {
        guard let set = dsSetBrightness else { return false }
        let clamped = Float(max(0, min(100, Int(percent)))) / 100
        return set(displayID, clamped) == 0
    }
}
