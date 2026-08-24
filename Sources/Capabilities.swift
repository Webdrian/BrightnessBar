import Foundation

// MARK: - What a monitor says it can do
//
// DDC/CI monitors can describe themselves: VCP 0xF3 returns a capability string listing every
// feature they implement. Reading it beats probing a fixed list of codes and hoping — it is
// the difference between "works on the monitor it was written for" and "works on any monitor".

struct DisplayCapabilities: Codable {

    /// Every VCP code the monitor claims to support.
    let supportedCodes: Set<UInt8>
    /// `model(...)` from the string, purely informational.
    let model: String?
    /// `mccs_ver(...)`, useful when a monitor misbehaves and someone reports it.
    let mccsVersion: String?
    /// The untouched string, kept so a bug report can include it.
    let raw: String

    var isEmpty: Bool { supportedCodes.isEmpty }

    func supports(_ code: VCPCode) -> Bool { supportedCodes.contains(code.rawValue) }

    /// Parses the parenthesised format, for example:
    /// `(prot(monitor)type(lcd)model(UN880)cmds(01 02 03)vcp(02 10 12 60(11 12) DF)mccs_ver(2.1))`
    ///
    /// Only the top level of `vcp(...)` counts: values in nested parentheses are the allowed
    /// settings of the preceding code, not codes themselves.
    init?(raw: String) {
        guard let vcpBody = DisplayCapabilities.section(named: "vcp", in: raw) else { return nil }

        var codes: Set<UInt8> = []
        var token = ""
        var depth = 0
        for character in vcpBody {
            switch character {
            case "(":
                depth += 1
                if depth == 1, let code = UInt8(token, radix: 16) { codes.insert(code) }
                token = ""
            case ")":
                depth = max(0, depth - 1)
                token = ""
            case " ", "\t", "\n":
                if depth == 0, let code = UInt8(token, radix: 16) { codes.insert(code) }
                token = ""
            default:
                token.append(character)
            }
        }
        if depth == 0, let code = UInt8(token, radix: 16) { codes.insert(code) }

        guard !codes.isEmpty else { return nil }
        self.supportedCodes = codes
        self.model = DisplayCapabilities.section(named: "model", in: raw)
        self.mccsVersion = DisplayCapabilities.section(named: "mccs_ver", in: raw)
        self.raw = raw
    }

    /// Returns the balanced contents of `name(...)`.
    private static func section(named name: String, in text: String) -> String? {
        guard let nameRange = text.range(of: name + "(") else { return nil }
        var depth = 1
        var result = ""
        var index = nameRange.upperBound
        while index < text.endIndex {
            let character = text[index]
            if character == "(" { depth += 1 }
            if character == ")" {
                depth -= 1
                if depth == 0 { return result }
            }
            result.append(character)
            index = text.index(after: index)
        }
        return nil
    }
}

// MARK: - Cache
//
// Reading the capability string costs a couple of seconds — a dozen round trips over a slow
// I²C bus. It never changes for a given monitor, so it is read once and remembered, keyed by
// the EDID identity rather than by display ID, which shifts between reboots.

enum CapabilityCache {

    private static func key(_ suffix: String, for identity: String) -> String {
        "caps.\(identity).\(suffix)"
    }

    static func capabilities(for identity: String) -> DisplayCapabilities? {
        guard let data = UserDefaults.standard.data(forKey: key("v1", for: identity)) else { return nil }
        return try? JSONDecoder().decode(DisplayCapabilities.self, from: data)
    }

    static func store(_ capabilities: DisplayCapabilities, for identity: String) {
        guard let data = try? JSONEncoder().encode(capabilities) else { return }
        UserDefaults.standard.set(data, forKey: key("v1", for: identity))
    }

    /// Set when a monitor answered nothing, so the slow read is not repeated at every launch.
    static func markUnsupported(for identity: String) {
        UserDefaults.standard.set(true, forKey: key("none", for: identity))
    }

    static func isKnownUnsupported(for identity: String) -> Bool {
        UserDefaults.standard.bool(forKey: key("none", for: identity))
    }

    /// The I²C settle time this monitor turned out to need, so the ladder is climbed once.
    static func settleIndex(for identity: String) -> Int? {
        UserDefaults.standard.object(forKey: key("settle", for: identity)) as? Int
    }

    static func storeSettleIndex(_ index: Int, for identity: String) {
        UserDefaults.standard.set(index, forKey: key("settle", for: identity))
    }

    static func forget(identity: String) {
        for suffix in ["v1", "none", "settle"] {
            UserDefaults.standard.removeObject(forKey: key(suffix, for: identity))
        }
    }
}
