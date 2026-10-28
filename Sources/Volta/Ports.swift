import Foundation
import IOKit

struct PortInfo: Identifiable, Equatable {
    var id: String { name }
    var name: String
    var isMagSafe: Bool
    var connected: Bool
    var transports: [String]
    var sourcingMilliamps: Int?   // current the Mac supplies to the accessory, when reported
}

struct USBDeviceInfo: Identifiable, Equatable {
    var id: UInt64
    var name: String
    var vendor: String?
    var allocatedMilliamps: Int?  // power budget granted by the Mac (5 V bus)
    var speed: String?

    var allocatedWatts: Double? { allocatedMilliamps.map { Double($0) * 5 / 1000 } }
}

enum PortsReader {
    private static func services(_ className: String) -> [io_object_t] {
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching(className), &iterator) == KERN_SUCCESS else { return [] }
        defer { IOObjectRelease(iterator) }
        var result: [io_object_t] = []
        while case let s = IOIteratorNext(iterator), s != 0 { result.append(s) }
        return result
    }

    private static func properties(_ s: io_object_t) -> [String: Any] {
        var props: Unmanaged<CFMutableDictionary>?
        guard IORegistryEntryCreateCFProperties(s, &props, kCFAllocatorDefault, 0) == KERN_SUCCESS else { return [:] }
        return props?.takeRetainedValue() as? [String: Any] ?? [:]
    }

    static func ports() -> [PortInfo] {
        services("AppleHPMInterface").compactMap { s in
            defer { IOObjectRelease(s) }
            let p = properties(s)
            guard let name = p["Description"] as? String, name.hasPrefix("Port-") else { return nil }
            let limits = (p["IOAccessoryPowerCurrentLimits"] as? [NSNumber])?.map(\.intValue) ?? []
            let sourcing = limits.max().flatMap { $0 > 0 ? $0 : nil }
            return PortInfo(
                name: name.replacingOccurrences(of: "Port-", with: ""),
                isMagSafe: name.contains("MagSafe"),
                connected: (p["ConnectionActive"] as? Bool) ?? false,
                transports: (p["TransportsActive"] as? [String]) ?? [],
                sourcingMilliamps: sourcing
            )
        }
        .sorted { ($0.isMagSafe ? 1 : 0, $0.name) < ($1.isMagSafe ? 1 : 0, $1.name) }
    }

    static func usbDevices() -> [USBDeviceInfo] {
        services("IOUSBHostDevice").compactMap { s in
            defer { IOObjectRelease(s) }
            let p = properties(s)
            var entryID: UInt64 = 0
            IORegistryEntryGetRegistryEntryID(s, &entryID)
            let name = (p["USB Product Name"] as? String) ?? (p["kUSBProductString"] as? String) ?? "Appareil USB"
            let milliamps = (p["UsbPowerSinkAllocation"] as? NSNumber)?.intValue
            let speeds = [0: "USB 1.1", 1: "USB 1.1", 2: "USB 2", 3: "USB 3 (5 Gb/s)", 4: "USB 3 (10 Gb/s)", 5: "USB 3 (20 Gb/s)"]
            return USBDeviceInfo(
                id: entryID,
                name: name,
                vendor: (p["USB Vendor Name"] as? String) ?? (p["kUSBVendorString"] as? String),
                allocatedMilliamps: milliamps.flatMap { $0 > 0 ? $0 : nil },
                speed: (p["UsbDeviceSpeed"] as? NSNumber).flatMap { speeds[$0.intValue] }
            )
        }
    }
}
