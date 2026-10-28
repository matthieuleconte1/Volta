import AppKit
import Darwin
import IOKit

@_silgen_name("responsibility_get_pid_responsible_for_pid")
private func responsiblePid(_ pid: pid_t) -> pid_t

/// Cumulative usage of a resource coalition (the per-app grouping Activity Monitor uses).
/// Readable for every coalition without root, and it keeps counting processes that already exited.
@_silgen_name("coalition_info_resource_usage")
private func coalitionResourceUsage(_ cid: UInt64, _ usage: UnsafeMutableRawPointer, _ size: Int) -> Int32

/// Leading fields of the kernel's `struct coalition_resource_usage`; the kernel copies at most `size` bytes.
private struct CoalitionUsage {
    var tasksStarted: UInt64 = 0, tasksExited: UInt64 = 0, timeNonempty: UInt64 = 0
    var cpuTime: UInt64 = 0                      // mach ticks
    var interruptWakeups: UInt64 = 0, platformIdleWakeups: UInt64 = 0, bytesRead: UInt64 = 0, bytesWritten: UInt64 = 0
    var gpuTime: UInt64 = 0, cpuTimeBilledToMe: UInt64 = 0, cpuTimeBilledToOthers: UInt64 = 0
    var energy: UInt64 = 0                       // nanojoules
}

private let PROC_PIDCOALITIONINFO: Int32 = 20

struct AppPower: Identifiable {
    let id: String            // grouping key (outermost executable / .app path of the coalition)
    let name: String
    let icon: NSImage?
    var cpuWatts: Double
    var gpuWatts: Double
    var cpuPercent: Double
    var gpuPercent: Double
    var processCount: Int

    var watts: Double { cpuWatts + gpuWatts }
}

/// Attributes CPU and GPU power to apps, grouped by resource coalition like Activity Monitor's Energy tab.
/// - CPU: the coalition's kernel energy counter (per-core-type energy model), so an app's helpers,
///   XPC services and already-exited children are included, and system daemons are measured too.
/// - GPU: per-process GPU time from the AGX driver, times the measured GPU power.
final class ProcessMonitor {
    private struct Counters { var cpuSeconds: Double; var energyJ: Double }
    private struct ProcessMeta { var coalition: UInt64; var groupPath: String? }
    private struct Group { var cpuWatts = 0.0, gpuWatts = 0.0, cpuPercent = 0.0, gpuPercent = 0.0, count = 0 }

    static let maxApps = 25

    private var previous: (time: TimeInterval, coalitions: [UInt64: Counters], gpu: [pid_t: Double])?
    private var meta: [pid_t: ProcessMeta] = [:]
    private var coalitionGroups: [UInt64: String] = [:]
    private var nameCache: [String: String] = [:]
    private var iconCache: [String: NSImage] = [:]
    private let ticksToSeconds: Double = {
        var tb = mach_timebase_info_data_t()
        mach_timebase_info(&tb)
        return Double(tb.numer) / Double(tb.denom) / 1e9
    }()

    func reset() {
        previous = nil
    }

    func sample(gpuWatts: Double?) -> [AppPower]? {
        let now = ProcessInfo.processInfo.systemUptime
        let pids = allPids()
        let gpu = gpuTimes()

        var members: [UInt64: [pid_t]] = [:]
        var alive: [pid_t: ProcessMeta] = [:]
        alive.reserveCapacity(pids.count)
        for pid in pids {
            guard let m = meta[pid] ?? processMeta(pid) else { continue }
            alive[pid] = m
            members[m.coalition, default: []].append(pid)
        }
        meta = alive
        coalitionGroups = coalitionGroups.filter { members[$0.key] != nil }

        var counters: [UInt64: Counters] = [:]
        counters.reserveCapacity(members.count)
        for (cid, pids) in members {
            var usage = CoalitionUsage()
            guard coalitionResourceUsage(cid, &usage, MemoryLayout<CoalitionUsage>.size) == 0 else { continue }
            counters[cid] = Counters(cpuSeconds: Double(usage.cpuTime) * ticksToSeconds, energyJ: Double(usage.energy) / 1e9)
            if coalitionGroups[cid] == nil, let path = groupPath(of: pids) { coalitionGroups[cid] = path }
        }

        defer { previous = (now, counters, gpu) }
        guard let prev = previous else { return nil }
        let dt = now - prev.time
        guard dt > 0.2 else { return nil }

        var groups: [String: Group] = [:]
        for (cid, c) in counters {
            guard let p = prev.coalitions[cid], let path = coalitionGroups[cid] else { continue }
            let cpu = max(0, c.cpuSeconds - p.cpuSeconds)
            let energy = max(0, c.energyJ - p.energyJ)
            var g = groups[path, default: Group()]
            g.cpuWatts += energy / dt
            g.cpuPercent += cpu / dt * 100
            g.count += members[cid]?.count ?? 0
            groups[path] = g
        }

        // GPU power is shared out by GPU time.
        var gpuDeltas: [pid_t: Double] = [:]
        for (pid, t) in gpu {
            guard let t0 = prev.gpu[pid], t > t0 else { continue }
            gpuDeltas[pid] = t - t0
        }
        let totalGPU = gpuDeltas.values.reduce(0, +)
        let gpuW = gpuWatts ?? 0
        for (pid, d) in gpuDeltas {
            guard let cid = meta[pid]?.coalition, let path = coalitionGroups[cid] else { continue }
            groups[path, default: Group()].gpuWatts += totalGPU > 0 ? gpuW * d / totalGPU : 0
            groups[path, default: Group()].gpuPercent += d / dt * 100
        }

        // Names and icons are only resolved (and cached) for the rows actually shown.
        return groups
            .filter { $0.value.cpuPercent > 0 || $0.value.gpuPercent > 0 }
            .sorted { $0.value.cpuWatts + $0.value.gpuWatts > $1.value.cpuWatts + $1.value.gpuWatts }
            .prefix(Self.maxApps)
            .map { path, g in
                AppPower(id: path, name: displayName(path), icon: icon(path),
                         cpuWatts: g.cpuWatts, gpuWatts: g.gpuWatts, cpuPercent: g.cpuPercent, gpuPercent: g.gpuPercent,
                         processCount: g.count)
            }
    }

    // MARK: - Sources

    private func allPids() -> [pid_t] {
        let count = proc_listallpids(nil, 0)
        guard count > 0 else { return [] }
        var pids = [pid_t](repeating: 0, count: Int(count) + 64)
        let n = proc_listallpids(&pids, Int32(pids.count * MemoryLayout<pid_t>.size))
        return Array(pids.prefix(Int(max(n, 0))))
    }

    private func processMeta(_ pid: pid_t) -> ProcessMeta? {
        // struct proc_pidcoalitioninfo: coalition_id[2] (resource, jetsam) + 3 reserved words.
        var info = (UInt64(0), UInt64(0), UInt64(0), UInt64(0), UInt64(0))
        let size = Int32(MemoryLayout.size(ofValue: info))
        guard proc_pidinfo(pid, PROC_PIDCOALITIONINFO, 0, &info, size) == size, info.0 != 0 else { return nil }
        let resp = responsiblePid(pid)
        let path = (resp > 0 && resp != pid ? executablePath(resp) : nil) ?? executablePath(pid)
        return ProcessMeta(coalition: info.0, groupPath: path.map(groupingPath))
    }

    /// Names a coalition after the app its members are responsible to: an .app bundle first,
    /// then the most common one, then the oldest (lowest pid, usually the coalition leader).
    private func groupPath(of pids: [pid_t]) -> String? {
        var votes: [String: (count: Int, minPid: pid_t)] = [:]
        for pid in pids {
            guard let path = meta[pid]?.groupPath else { continue }
            let v = votes[path] ?? (0, pid)
            votes[path] = (v.count + 1, min(v.minPid, pid))
        }
        return votes.max { a, b in
            let aApp = a.key.hasSuffix(".app"), bApp = b.key.hasSuffix(".app")
            if aApp != bApp { return !aApp }
            if a.value.count != b.value.count { return a.value.count < b.value.count }
            return a.value.minPid > b.value.minPid
        }?.key
    }

    /// Cumulative GPU time per pid, published by the GPU driver's user clients.
    private func gpuTimes() -> [pid_t: Double] {
        var result: [pid_t: Double] = [:]
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("IOAccelerator"), &iterator) == KERN_SUCCESS else { return result }
        defer { IOObjectRelease(iterator) }
        while case let accel = IOIteratorNext(iterator), accel != 0 {
            defer { IOObjectRelease(accel) }
            var children: io_iterator_t = 0
            guard IORegistryEntryGetChildIterator(accel, kIOServicePlane, &children) == KERN_SUCCESS else { continue }
            while case let child = IOIteratorNext(children), child != 0 {
                defer { IOObjectRelease(child) }
                guard let usage = IORegistryEntryCreateCFProperty(child, "AppUsage" as CFString, kCFAllocatorDefault, 0)?
                        .takeRetainedValue() as? [[String: Any]], !usage.isEmpty,
                      let creator = IORegistryEntryCreateCFProperty(child, "IOUserClientCreator" as CFString, kCFAllocatorDefault, 0)?
                        .takeRetainedValue() as? String
                else { continue }
                // "pid 181, WindowServer"
                guard let pidPart = creator.split(separator: ",").first?.split(separator: " ").last,
                      let pid = pid_t(pidPart) else { continue }
                let ns = usage.reduce(0.0) { $0 + ((($1["accumulatedGPUTime"]) as? NSNumber)?.doubleValue ?? 0) }
                result[pid, default: 0] += ns / 1e9
            }
            IOObjectRelease(children)
        }
        return result
    }

    // MARK: - Naming

    private func executablePath(_ pid: pid_t) -> String? {
        var buf = [CChar](repeating: 0, count: Int(MAXPATHLEN) * 4)
        guard proc_pidpath(pid, &buf, UInt32(buf.count)) > 0 else { return nil }
        return String(cString: buf)
    }

    /// Collapses helpers into their outermost .app bundle.
    private func groupingPath(_ path: String) -> String {
        if let range = path.range(of: ".app/") {
            return String(path[..<range.lowerBound]) + ".app"
        }
        return path
    }

    private func displayName(_ groupPath: String) -> String {
        if let cached = nameCache[groupPath] { return cached }
        let name = resolveName(groupPath)
        nameCache[groupPath] = name
        return name
    }

    private func resolveName(_ groupPath: String) -> String {
        if groupPath.hasSuffix(".app") {
            let bundle = Bundle(path: groupPath)
            let name = bundle?.localizedInfoDictionary?["CFBundleDisplayName"] as? String
                ?? bundle?.infoDictionary?["CFBundleDisplayName"] as? String
                ?? bundle?.infoDictionary?["CFBundleName"] as? String
            return name ?? URL(fileURLWithPath: groupPath).deletingPathExtension().lastPathComponent
        }
        let last = URL(fileURLWithPath: groupPath).lastPathComponent
        return last.isEmpty ? groupPath : last
    }

    private func icon(_ groupPath: String) -> NSImage? {
        guard groupPath.hasSuffix(".app") else { return nil }
        if let cached = iconCache[groupPath] { return cached }
        let image = NSWorkspace.shared.icon(forFile: groupPath)
        image.size = NSSize(width: 32, height: 32)
        iconCache[groupPath] = image
        return image
    }
}
