import Foundation
import CoreAudio
import AudioToolbox

// MARK: - Where the sound is actually going
//
// The volume keys belong to whatever is playing. macOS handles every device whose volume it
// can set itself — headphones, speakers, USB interfaces. This app exists only for the case it
// cannot: monitor speakers over DisplayPort or HDMI, which frequently expose no volume control
// at all, so the keys show the crossed-out speaker and do nothing.
//
// Deciding by that capability rather than by "is a monitor plugged in" keeps the two apart. An
// earlier version asked only whether *some* monitor could do volume, and happily turned the
// monitor down while the user was wearing headphones.

enum AudioOutput {

    struct Device {
        let name: String
        let transport: UInt32
        /// True when macOS can set this device's volume on its own — then the keys are none of
        /// this app's business.
        let systemControllable: Bool

        /// DisplayPort or HDMI, the two transports that carry monitor audio.
        var isDisplayAttached: Bool {
            transport == kAudioDeviceTransportTypeDisplayPort || transport == kAudioDeviceTransportTypeHDMI
        }

        /// CoreAudio names a monitor's audio device after the monitor itself, which is what
        /// links the two together when several displays have speakers.
        func matches(displayName: String) -> Bool {
            let a = name.lowercased().trimmingCharacters(in: .whitespaces)
            let b = displayName.lowercased().trimmingCharacters(in: .whitespaces)
            guard !a.isEmpty, !b.isEmpty else { return false }
            return a == b || a.contains(b) || b.contains(a)
        }
    }

    static var current: Device? {
        guard let id = defaultOutputDeviceID() else { return nil }
        return Device(
            name: stringProperty(id, kAudioObjectPropertyName) ?? "",
            transport: uint32Property(id, kAudioDevicePropertyTransportType) ?? 0,
            systemControllable: hasProperty(id, kAudioHardwareServiceDeviceProperty_VirtualMainVolume)
                || hasProperty(id, kAudioDevicePropertyVolumeScalar, element: 1)
                || hasProperty(id, kAudioDevicePropertyVolumeScalar, element: 0)
        )
    }

    // MARK: CoreAudio plumbing

    private static func defaultOutputDeviceID() -> AudioDeviceID? {
        var id = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject),
                                         &address, 0, nil, &size, &id) == noErr, id != 0 else { return nil }
        return id
    }

    private static func stringProperty(_ id: AudioDeviceID, _ selector: AudioObjectPropertySelector) -> String? {
        var address = AudioObjectPropertyAddress(mSelector: selector,
                                                 mScope: kAudioObjectPropertyScopeGlobal,
                                                 mElement: kAudioObjectPropertyElementMain)
        // Taking a pointer to an Optional<CFString> is unsound; CoreAudio writes a retained
        // reference into raw storage, so it is unwrapped explicitly.
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        var value: Unmanaged<CFString>?
        let status = withUnsafeMutablePointer(to: &value) { pointer in
            AudioObjectGetPropertyData(id, &address, 0, nil, &size, pointer)
        }
        guard status == noErr, let string = value?.takeRetainedValue() else { return nil }
        return string as String
    }

    private static func uint32Property(_ id: AudioDeviceID, _ selector: AudioObjectPropertySelector) -> UInt32? {
        var address = AudioObjectPropertyAddress(mSelector: selector,
                                                 mScope: kAudioObjectPropertyScopeGlobal,
                                                 mElement: kAudioObjectPropertyElementMain)
        var value: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        guard AudioObjectGetPropertyData(id, &address, 0, nil, &size, &value) == noErr else { return nil }
        return value
    }

    private static func hasProperty(_ id: AudioDeviceID,
                                    _ selector: AudioObjectPropertySelector,
                                    element: AudioObjectPropertyElement = kAudioObjectPropertyElementMain) -> Bool {
        var address = AudioObjectPropertyAddress(mSelector: selector,
                                                 mScope: kAudioDevicePropertyScopeOutput,
                                                 mElement: element)
        return AudioObjectHasProperty(id, &address)
    }
}
