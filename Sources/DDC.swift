import Foundation
import IOKit

// MARK: - Private IOAVService bridge
//
// Apple Silicon has no public I²C API for external displays. The DDC/CI path goes
// through IOAVService, which lives in IOKit but is not declared in any header, so
// the four entry points are resolved at runtime.

private let ioKitHandle: UnsafeMutableRawPointer? =
    dlopen("/System/Library/Frameworks/IOKit.framework/IOKit", RTLD_LAZY)

private typealias CreateWithServiceFn = @convention(c) (CFAllocator?, io_service_t) -> Unmanaged<CFTypeRef>?
private typealias I2CFn = @convention(c) (CFTypeRef, UInt32, UInt32, UnsafeMutableRawPointer, UInt32) -> IOReturn

private func sym<T>(_ name: String, as type: T.Type) -> T? {
    guard let handle = ioKitHandle, let p = dlsym(handle, name) else { return nil }
    return unsafeBitCast(p, to: T.self)
}

private let avCreateWithService = sym("IOAVServiceCreateWithService", as: CreateWithServiceFn.self)
private let avWriteI2C = sym("IOAVServiceWriteI2C", as: I2CFn.self)
private let avReadI2C = sym("IOAVServiceReadI2C", as: I2CFn.self)

/// True when this machine exposes the IOAVService DDC entry points at all.
var ddcRuntimeAvailable: Bool {
    avCreateWithService != nil && avWriteI2C != nil && avReadI2C != nil
}

func makeAVService(from entry: io_service_t) -> CFTypeRef? {
    avCreateWithService?(kCFAllocatorDefault, entry)?.takeRetainedValue()
}

// MARK: - VCP codes

enum VCPCode: UInt8, CaseIterable {
    case brightness = 0x10
    case contrast = 0x12
    case speakerVolume = 0x62
    /// MCCS calls this "Audio Mute": 1 mutes, 2 unmutes. It is not a 0-100 scale despite
    /// what the display reports as its maximum.
    case audioMute = 0x8D

    var label: String {
        switch self {
        case .brightness: return "Helligkeit"
        case .contrast: return "Kontrast"
        case .speakerVolume: return "Lautstärke"
        case .audioMute: return "Stumm"
        }
    }
}

/// The two values MCCS defines for `audioMute`.
enum AudioMuteState: UInt16 {
    case muted = 1
    case unmuted = 2
}

// MARK: - Probe outcome

/// Why a display did or did not answer. The distinction matters: a display that refuses to
/// *answer* often still accepts commands, but one whose I²C channel the kernel will not even
/// carry cannot be controlled at all, and must not be offered a slider.
enum DDCProbeResult {
    case value(current: UInt16, max: UInt16)
    /// The request went out, the display stayed silent.
    case noReply
    /// The kernel refused the transaction outright — no adapter or hub in the path forwards
    /// DDC. Observed as 0xE0114000 on a DP→HDMI converter and on a DP 1.2 branch device.
    case busUnavailable(IOReturn)
}

// MARK: - DDC/CI link to one display

/// One I²C channel to one external display.
///
/// All traffic is serialised on a private queue. Writes are coalesced, so dragging a
/// slider sends only the values the bus can actually keep up with instead of flooding it.
final class DDCLink {

    // DDC/CI wire constants
    private let chipAddress: UInt32 = 0x37      // 0x6E >> 1
    private let dataOffset: UInt32 = 0x51       // host address, doubles as the I²C offset
    private let hostAddress: UInt8 = 0x51
    private let displayAddress: UInt8 = 0x6E
    private let replyLengthByte: UInt8 = 0x88   // 0x80 | 8 data bytes in a VCP feature reply
    private let replyChecksumSeed: UInt8 = 0x50

    // Timing, empirically tuned on an LG HDR 4K over DisplayPort.
    private let interWriteDelay: UInt32 = 10_000     // between the two request writes
    private let readSettleDelay: UInt32 = 80_000     // before pulling the reply off the bus
    private let retryDelay: UInt32 = 100_000
    private let postWriteDelay: UInt32 = 15_000      // bus cool-down after a Set
    private let readAttempts = 4

    private let avService: CFTypeRef
    private let queue: DispatchQueue

    private let lock = NSLock()
    private var pending: [VCPCode: UInt16] = [:]
    private var draining = false

    /// Called on the main queue when the kernel refuses to carry a write, so a display that
    /// loses its DDC path (re-plugged behind an adapter) stops pretending to be adjustable.
    var busFailureHandler: (() -> Void)?

    init(avService: CFTypeRef, label: String) {
        self.avService = avService
        self.queue = DispatchQueue(label: "brightnessbar.ddc.\(label)", qos: .userInitiated)
    }

    // MARK: Public API

    /// Queues a value. Repeated calls before the bus catches up keep only the newest one.
    func schedule(_ vcp: VCPCode, value: UInt16) {
        lock.lock()
        pending[vcp] = value
        let startDrain = !draining
        if startDrain { draining = true }
        lock.unlock()

        if startDrain { queue.async { self.drain() } }
    }

    /// Reads a VCP feature. `nil` means the display did not answer a valid reply.
    func read(_ vcp: VCPCode, completion: @escaping ((current: UInt16, max: UInt16)?) -> Void) {
        queue.async {
            var result: (current: UInt16, max: UInt16)?
            if case .value(let current, let max) = self.performProbe(vcp) {
                result = (current, max)
            }
            DispatchQueue.main.async { completion(result) }
        }
    }

    /// Synchronous read, for startup enumeration off the main thread.
    func readSync(_ vcp: VCPCode) -> (current: UInt16, max: UInt16)? {
        if case .value(let current, let max) = queue.sync(execute: { performProbe(vcp) }) {
            return (current, max)
        }
        return nil
    }

    /// Synchronous probe that also distinguishes a silent display from a dead I²C channel.
    func probeSync(_ vcp: VCPCode) -> DDCProbeResult {
        queue.sync { performProbe(vcp) }
    }

    /// Fire-and-forget write that waits for the bus, used on quit/restore paths.
    func writeSync(_ vcp: VCPCode, value: UInt16) -> Bool {
        queue.sync { performWrite(vcp, value) }
    }

    // MARK: Draining

    private func drain() {
        while true {
            lock.lock()
            guard let (vcp, value) = pending.popFirst() else {
                draining = false
                lock.unlock()
                return
            }
            lock.unlock()

            _ = performWrite(vcp, value)
            usleep(postWriteDelay)
        }
    }

    // MARK: Wire format

    /// Set VCP Feature: [0x84][0x03][vcp][hi][lo][checksum]
    private func performWrite(_ vcp: VCPCode, _ value: UInt16) -> Bool {
        var packet: [UInt8] = [0x84, 0x03, vcp.rawValue, UInt8(value >> 8), UInt8(value & 0xFF), 0]
        packet[5] = checksum(of: packet[0...4], seed: displayAddress ^ hostAddress)

        // Two cycles: a single Set is occasionally dropped on a busy bus.
        var ok = false
        var lastError: IOReturn = KERN_SUCCESS
        for cycle in 0..<2 {
            let rc = send(&packet)
            if rc == KERN_SUCCESS { ok = true } else { lastError = rc }
            if cycle == 0 { usleep(interWriteDelay) }
        }
        if !ok, lastError != KERN_SUCCESS, let handler = busFailureHandler {
            DispatchQueue.main.async(execute: handler)
        }
        return ok
    }

    /// Get VCP Feature: [0x82][0x01][vcp][checksum], then read the 11-byte reply.
    ///
    /// The request has to go out **twice**. With a single request this display returns a
    /// stale buffer every time; with two it answers reliably.
    private func performProbe(_ vcp: VCPCode) -> DDCProbeResult {
        var lastWriteError: IOReturn = KERN_SUCCESS
        var anyWriteSucceeded = false

        for attempt in 0..<readAttempts {
            var request: [UInt8] = [0x82, 0x01, vcp.rawValue, 0]
            request[3] = checksum(of: request[0...2], seed: displayAddress ^ hostAddress)

            for _ in 0..<2 {
                let rc = send(&request)
                if rc == KERN_SUCCESS { anyWriteSucceeded = true } else { lastWriteError = rc }
                usleep(interWriteDelay)
            }
            // A refused write means the channel itself is gone; retrying cannot help.
            guard anyWriteSucceeded else { break }

            usleep(readSettleDelay)

            var reply = [UInt8](repeating: 0, count: 12)
            let rc = reply.withUnsafeMutableBytes {
                avReadI2C?(avService, chipAddress, dataOffset, $0.baseAddress!, UInt32($0.count)) ?? KERN_FAILURE
            }
            if rc == KERN_SUCCESS, let parsed = parseReply(reply, expecting: vcp) {
                return .value(current: parsed.current, max: parsed.max)
            }
            if attempt < readAttempts - 1 { usleep(retryDelay) }
        }

        return anyWriteSucceeded ? .noReply : .busUnavailable(lastWriteError)
    }

    private func send(_ packet: inout [UInt8]) -> IOReturn {
        packet.withUnsafeMutableBytes {
            avWriteI2C?(avService, chipAddress, dataOffset, $0.baseAddress!, UInt32($0.count)) ?? KERN_FAILURE
        }
    }

    /// Reply layout: [0x6E][len][0x02][result][vcp][type][maxHi][maxLo][curHi][curLo][checksum]
    ///
    /// IOAVServiceReadI2C overwrites byte 1 (the length byte) with the I²C offset it read
    /// from, so the length is substituted back in before verifying the checksum.
    private func parseReply(_ reply: [UInt8], expecting vcp: VCPCode) -> (current: UInt16, max: UInt16)? {
        guard reply.count >= 11,
              reply[0] == displayAddress,
              reply[2] == 0x02,          // VCP feature reply
              reply[3] == 0x00,          // result code: no error
              reply[4] == vcp.rawValue
        else { return nil }

        var expected = replyChecksumSeed ^ displayAddress ^ replyLengthByte
        for i in 2...9 { expected ^= reply[i] }
        guard expected == reply[10] else { return nil }

        let maxValue = UInt16(reply[6]) << 8 | UInt16(reply[7])
        let current = UInt16(reply[8]) << 8 | UInt16(reply[9])
        guard maxValue > 0 else { return nil }
        return (current, maxValue)
    }

    private func checksum(of bytes: ArraySlice<UInt8>, seed: UInt8) -> UInt8 {
        bytes.reduce(seed) { $0 ^ $1 }
    }
}
