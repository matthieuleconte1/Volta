import Foundation

/// Reads the SoC "Energy Model" counters through the private libIOReport
/// (same source as powermetrics, but without root).
final class EnergyModelReader {
    private typealias CopyChannelsInGroup = @convention(c) (CFString?, CFString?, UInt64, UInt64, UInt64) -> Unmanaged<CFMutableDictionary>?
    private typealias CreateSubscription = @convention(c) (UnsafeMutableRawPointer?, CFMutableDictionary, UnsafeMutablePointer<Unmanaged<CFMutableDictionary>?>, UInt64, CFTypeRef?) -> OpaquePointer?
    private typealias CreateSamples = @convention(c) (OpaquePointer, CFMutableDictionary, CFTypeRef?) -> Unmanaged<CFDictionary>?
    private typealias CreateSamplesDelta = @convention(c) (CFDictionary, CFDictionary, CFTypeRef?) -> Unmanaged<CFDictionary>?
    private typealias ChannelString = @convention(c) (CFDictionary) -> Unmanaged<CFString>?
    private typealias SimpleIntegerValue = @convention(c) (CFDictionary, Int32) -> Int64

    private let createSamples: CreateSamples
    private let createDelta: CreateSamplesDelta
    private let channelName: ChannelString
    private let unitLabel: ChannelString
    private let integerValue: SimpleIntegerValue
    private let subscription: OpaquePointer
    private let subscribed: CFMutableDictionary

    private let suffixes: [String]
    private var previous: (sample: CFDictionary, time: TimeInterval)?
    /// Channels whose counter moved at the previous call.
    private var moving: Set<String> = []

    /// - Parameter channels: restricts the subscription to the channels whose name ends with one of these
    ///   (cheaper sampling). Like Stats, a suffix also catches per-die channels ("DIE_1_CPU Energy" on Ultra chips),
    ///   which are summed under the suffix.
    init?(channels wanted: Set<String>? = nil) {
        guard let lib = dlopen("/usr/lib/libIOReport.dylib", RTLD_NOW),
              let copyPtr = dlsym(lib, "IOReportCopyChannelsInGroup"),
              let subPtr = dlsym(lib, "IOReportCreateSubscription"),
              let samplesPtr = dlsym(lib, "IOReportCreateSamples"),
              let deltaPtr = dlsym(lib, "IOReportCreateSamplesDelta"),
              let namePtr = dlsym(lib, "IOReportChannelGetChannelName"),
              let unitPtr = dlsym(lib, "IOReportChannelGetUnitLabel"),
              let valuePtr = dlsym(lib, "IOReportSimpleGetIntegerValue")
        else { return nil }

        let copyChannels = unsafeBitCast(copyPtr, to: CopyChannelsInGroup.self)
        let createSubscription = unsafeBitCast(subPtr, to: CreateSubscription.self)
        createSamples = unsafeBitCast(samplesPtr, to: CreateSamples.self)
        createDelta = unsafeBitCast(deltaPtr, to: CreateSamplesDelta.self)
        channelName = unsafeBitCast(namePtr, to: ChannelString.self)
        unitLabel = unsafeBitCast(unitPtr, to: ChannelString.self)
        integerValue = unsafeBitCast(valuePtr, to: SimpleIntegerValue.self)

        guard let channels = copyChannels("Energy Model" as CFString, nil, 0, 0, 0)?.takeRetainedValue() else { return nil }
        if let wanted, let all = (channels as NSDictionary)["IOReportChannels"] as? [NSDictionary] {
            let nameOf = unsafeBitCast(namePtr, to: ChannelString.self)
            let kept = all.filter { item in
                guard let name = nameOf(item as CFDictionary)?.takeUnretainedValue() as String? else { return false }
                return wanted.contains { name.hasSuffix($0) }
            }
            guard !kept.isEmpty else { return nil }
            (channels as NSMutableDictionary)["IOReportChannels"] = kept
        }
        var out: Unmanaged<CFMutableDictionary>?
        guard let sub = createSubscription(nil, channels, &out, 0, nil), let subbed = out?.takeRetainedValue() else { return nil }
        subscription = sub
        subscribed = subbed
        suffixes = wanted.map(Array.init) ?? []
    }

    /// Average power in watts per channel (or per suffix given at init) since the previous call.
    /// A channel is only reported once its counter moved at two calls in a row: some counters are dead
    /// on recent macOS (CPU, DRAM, ANE on macOS 27) and others are only refreshed now and then, which would
    /// show their whole backlog as a spike. The caller falls back to the SMC sensors for missing channels.
    func sample() -> [String: Double] {
        guard let current = createSamples(subscription, subscribed, nil)?.takeRetainedValue() else { return [:] }
        let now = ProcessInfo.processInfo.systemUptime
        defer { previous = (current, now) }
        guard let prev = previous, now - prev.time > 0.05,
              let delta = createDelta(prev.sample, current, nil)?.takeRetainedValue() as NSDictionary?,
              let items = delta["IOReportChannels"] as? [NSDictionary]
        else { return [:] }

        let dt = now - prev.time
        var result: [String: Double] = [:]
        var moved: Set<String> = []
        defer { moving = moved }
        for item in items {
            let channel = item as CFDictionary
            guard let full = channelName(channel)?.takeUnretainedValue() as String? else { continue }
            let name = suffixes.first { full.hasSuffix($0) } ?? full
            let value = integerValue(channel, 0)
            guard value > 0 else { continue }
            moved.insert(name)
            guard moving.contains(name) else { continue }
            let unit = unitLabel(channel)?.takeUnretainedValue() as String? ?? ""
            let joules: Double
            switch unit {
            case "nJ": joules = Double(value) / 1e9
            case "uJ": joules = Double(value) / 1e6
            case "mJ": joules = Double(value) / 1e3
            default: continue
            }
            result[name, default: 0] += joules / dt
        }
        return result
    }
}
