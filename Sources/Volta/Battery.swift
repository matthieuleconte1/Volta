import Foundation
import IOKit

struct AdapterInfo: Equatable {
    var name: String?
    var manufacturer: String?
    var watts: Double?
    var voltage: Double?   // V (negotiated)
    var current: Double?   // A (max)
    var isWireless = false
}

struct BatteryInfo: Equatable {
    var percent: Int = 0
    var isCharging = false
    var externalConnected = false
    var fullyCharged = false
    var voltage: Double = 0          // V
    var amperage: Double = 0         // A, > 0 when charging
    var cycleCount: Int?
    var designCapacity: Int?         // mAh
    var fullChargeCapacity: Int?     // mAh
    var currentCapacity: Int?        // mAh
    var temperature: Double?         // °C
    var minutesRemaining: Int?       // to empty (on battery) or to full (charging)
    // Power telemetry reported by the charger IC (W)
    var systemLoad: Double?
    var systemPowerIn: Double?
    var inputVoltage: Double?
    var inputCurrent: Double?
    var adapter: AdapterInfo?

    var health: Double? {
        guard let full = fullChargeCapacity, let design = designCapacity, design > 0 else { return nil }
        return Double(full) / Double(design)
    }
}

enum BatteryReader {
    static func read() -> BatteryInfo? {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSmartBattery"))
        guard service != 0 else { return nil }
        defer { IOObjectRelease(service) }
        var props: Unmanaged<CFMutableDictionary>?
        guard IORegistryEntryCreateCFProperties(service, &props, kCFAllocatorDefault, 0) == KERN_SUCCESS,
              let dict = props?.takeRetainedValue() as? [String: Any]
        else { return nil }
        let data = dict["BatteryData"] as? [String: Any] ?? [:]

        func int(_ key: String, in d: [String: Any]? = nil) -> Int64? {
            guard let n = (d ?? dict)[key] as? NSNumber else { return nil }
            return Int64(bitPattern: n.uint64Value)
        }
        func either(_ key: String) -> Int? { (int(key) ?? int(key, in: data)).map(Int.init) }
        func bool(_ key: String) -> Bool { (dict[key] as? Bool) ?? false }

        var info = BatteryInfo()
        info.percent = either("CurrentCapacity") ?? 0
        info.isCharging = bool("IsCharging")
        info.externalConnected = bool("ExternalConnected")
        info.fullyCharged = bool("FullyCharged")
        info.voltage = Double(int("Voltage") ?? 0) / 1000
        info.amperage = Double(int("InstantAmperage") ?? int("Amperage") ?? 0) / 1000
        info.cycleCount = either("CycleCount")
        info.designCapacity = either("DesignCapacity")
        info.fullChargeCapacity = either("AppleRawMaxCapacity") ?? either("FullChargeCapacity")
        info.currentCapacity = either("AppleRawCurrentCapacity")
        if let t = either("Temperature") ?? either("VirtualTemperature") { info.temperature = Double(t) / 100 }

        let remaining = info.isCharging ? either("AvgTimeToFull") : either("TimeRemaining")
        if let r = remaining, r > 0, r < 65535 { info.minutesRemaining = r }

        if let tel = dict["PowerTelemetryData"] as? [String: Any] {
            func w(_ k: String) -> Double? { int(k, in: tel).map { Double($0) / 1000 } }
            info.systemLoad = w("SystemLoad")
            info.systemPowerIn = w("SystemPowerIn")
            info.inputVoltage = w("SystemVoltageIn")
            info.inputCurrent = w("SystemCurrentIn")
        }

        if info.externalConnected, let a = dict["AdapterDetails"] as? [String: Any] {
            var adapter = AdapterInfo()
            adapter.name = (a["Name"] as? String) ?? (a["Description"] as? String)
            adapter.manufacturer = a["Manufacturer"] as? String
            adapter.watts = (a["Watts"] as? NSNumber)?.doubleValue
            adapter.voltage = (a["AdapterVoltage"] as? NSNumber).map { $0.doubleValue / 1000 }
            adapter.current = (a["Current"] as? NSNumber).map { $0.doubleValue / 1000 }
            adapter.isWireless = (a["IsWireless"] as? Bool) ?? false
            info.adapter = adapter
        }
        return info
    }
}
