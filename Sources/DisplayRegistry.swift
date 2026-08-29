import Foundation
import IOKit
import CoreGraphics
import AppKit

// MARK: - IORegistry helpers

private func registryName(_ entry: io_registry_entry_t) -> String {
    var buf = [CChar](repeating: 0, count: 128)
    IORegistryEntryGetName(entry, &buf)
    return String(cString: buf)
}

private func objectClass(_ entry: io_registry_entry_t) -> String {
    var buf = [CChar](repeating: 0, count: 128)
    IOObjectGetClass(entry, &buf)
    return String(cString: buf)
}

private func registryPath(_ entry: io_registry_entry_t) -> String {
    var buf = [CChar](repeating: 0, count: 4096)
    IORegistryEntryGetPath(entry, kIOServicePlane, &buf)
    return String(cString: buf)
}

private func properties(_ entry: io_registry_entry_t) -> [String: Any] {
    var unmanaged: Unmanaged<CFMutableDictionary>?
    guard IORegistryEntryCreateCFProperties(entry, &unmanaged, kCFAllocatorDefault, 0) == KERN_SUCCESS,
          let dict = unmanaged?.takeRetainedValue() as? [String: Any]
    else { return [:] }
    return dict
}

/// Pulls the `dispN` / `dispextN` / `dcpN` / `dcpextN` node out of a registry path.
private func nodeKey(in path: String, prefix: String) -> String? {
    for component in path.split(separator: "/") {
        let name = component.split(separator: "@").first.map(String.init) ?? String(component)
        if name == prefix || (name.hasPrefix(prefix) && name.dropFirst(prefix.count).allSatisfy(\.isNumber)) {
            return name
        }
        if name.hasPrefix(prefix + "ext"),
           name.dropFirst(prefix.count + 3).allSatisfy(\.isNumber) {
            return name
        }
    }
    return nil
}

/// `dcp` drives `disp0`, `dcpext0` drives `dispext0`, and so on.
private func framebufferKey(forDCP dcp: String) -> String {
    if dcp == "dcp" { return "disp0" }
    if dcp.hasPrefix("dcpext") { return "dispext" + dcp.dropFirst(6) }
    return dcp
}

// MARK: - Enumeration result

struct DiscoveredDisplay {
    let displayID: CGDirectDisplayID
    let name: String
    let serialText: String
    let framebufferKey: String
    let isBuiltIn: Bool
    /// True for AirPlay screens, which have no physical link and therefore no DDC channel.
    let isAirPlay: Bool
    let avService: CFTypeRef?

    /// Stable across reboots and reconnections, unlike `displayID` — used to key everything
    /// remembered about this particular monitor.
    var cacheIdentity: String {
        serialText.isEmpty ? name : "\(name).\(serialText)"
    }
}

enum DisplayRegistry {

    /// Matches every online CoreGraphics display against its IORegistry framebuffer node
    /// (by EDID vendor / product / serial) and, through the framebuffer's DCP instance,
    /// against the DDC-capable IOAVService that talks to it.
    static func discover() -> [DiscoveredDisplay] {
        var framebuffers: [String: (vendor: UInt32, product: UInt32, serial: UInt32, name: String, serialText: String)] = [:]
        var avEntries: [String: io_service_t] = [:]

        let root = IORegistryGetRootEntry(kIOMainPortDefault)
        var iterator = io_iterator_t()
        guard IORegistryEntryCreateIterator(
            root, kIOServicePlane, IOOptionBits(kIORegistryIterateRecursively), &iterator
        ) == KERN_SUCCESS else { return [] }

        while case let entry = IOIteratorNext(iterator), entry != 0 {
            var keepEntry = false
            let props = properties(entry)

            if let attributes = props["DisplayAttributes"] as? [String: Any],
               let product = attributes["ProductAttributes"] as? [String: Any],
               let key = nodeKey(in: registryPath(entry), prefix: "disp") {
                framebuffers[key] = (
                    vendor: (product["LegacyManufacturerID"] as? NSNumber)?.uint32Value ?? 0,
                    product: (product["ProductID"] as? NSNumber)?.uint32Value ?? 0,
                    serial: (product["SerialNumber"] as? NSNumber)?.uint32Value ?? 0,
                    name: (product["ProductName"] as? String) ?? registryName(entry),
                    serialText: (product["AlphanumericSerialNumber"] as? String) ?? ""
                )
            }

            if objectClass(entry) == "DCPAVServiceProxy",
               (props["Location"] as? String) == "External",
               let dcpKey = nodeKey(in: registryPath(entry), prefix: "dcp") {
                avEntries[framebufferKey(forDCP: dcpKey)] = entry
                keepEntry = true
            }

            if !keepEntry { IOObjectRelease(entry) }
        }
        IOObjectRelease(iterator)

        defer { avEntries.values.forEach { IOObjectRelease($0) } }

        var onlineCount: UInt32 = 0
        CGGetOnlineDisplayList(32, nil, &onlineCount)
        var displayIDs = [CGDirectDisplayID](repeating: 0, count: Int(onlineCount))
        CGGetOnlineDisplayList(onlineCount, &displayIDs, &onlineCount)

        var results: [DiscoveredDisplay] = []
        for displayID in displayIDs.prefix(Int(onlineCount)) {
            guard CGDisplayIsAsleep(displayID) == 0 else { continue }

            let vendor = CGDisplayVendorNumber(displayID)
            let model = CGDisplayModelNumber(displayID)
            let serial = CGDisplaySerialNumber(displayID)
            let builtIn = CGDisplayIsBuiltin(displayID) != 0

            let match = framebuffers.first { _, fb in
                fb.vendor == vendor && fb.product == model && fb.serial == serial
            }

            let key = match?.key ?? "?"
            let info = match?.value
            let avService = avEntries[key].flatMap { makeAVService(from: $0) }

            results.append(DiscoveredDisplay(
                displayID: displayID,
                name: info?.name ?? fallbackName(for: displayID, builtIn: builtIn),
                serialText: info?.serialText ?? "",
                framebufferKey: key,
                isBuiltIn: builtIn,
                isAirPlay: isAirPlay(displayID),
                avService: builtIn ? nil : avService
            ))
        }
        return results
    }

    /// Not every display publishes EDID data. An AirPlay screen has no physical connection at
    /// all, so there is nothing to read — but macOS still knows what to call it, and a name
    /// beats "Display 8".
    private static func fallbackName(for displayID: CGDirectDisplayID, builtIn: Bool) -> String {
        if builtIn { return L("Internes Display") }
        if let name = screenName(for: displayID), !name.isEmpty { return name }
        return L("Display %u", displayID)
    }

    private static func screenName(for displayID: CGDirectDisplayID) -> String? {
        NSScreen.screens.first {
            ($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value == displayID
        }?.localizedName
    }

    /// AirPlay screens identify themselves with the four-character codes "aapl" and "airp".
    /// Worth telling apart: their lack of DDC is not a cabling problem anyone could fix.
    static func isAirPlay(_ displayID: CGDirectDisplayID) -> Bool {
        CGDisplayVendorNumber(displayID) == 0x6161_706C && CGDisplayModelNumber(displayID) == 0x6169_7270
    }
}
