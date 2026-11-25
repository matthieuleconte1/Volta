import AppKit
import Combine

struct PowerSnapshot {
    var system: Double?        // W consumed by the whole Mac
    var adapterIn: Double?     // W delivered by the charger
    var battery: Double?       // W, > 0 charging, < 0 discharging
    var cpu: Double?
    var gpu: Double?
    var display: Double?       // built-in display backlight
    var soc: Double?           // rest of the chip: SMC heatpipe power − CPU − GPU
    var batteryInfo: BatteryInfo?

    var other: Double? {
        guard let system else { return nil }
        return max(0, system - (cpu ?? 0) - (gpu ?? 0) - (display ?? 0) - (soc ?? 0))
    }
    var onAC: Bool { batteryInfo?.externalConnected ?? ((adapterIn ?? 0) > 0.5) }
    var charging: Bool { (battery ?? 0) > 0.3 }
}

struct HistoryPoint: Identifiable {
    let id = UUID()
    let date: Date
    let system: Double
    let cpu: Double
    let gpu: Double
    let display: Double
    let soc: Double
    var other: Double { max(0, system - cpu - gpu - display - soc) }
}

enum MenuBarMetric: String, CaseIterable, Identifiable {
    case system, adapter, battery
    var id: String { rawValue }
    var label: String { L(labelFR) }
    private var labelFR: String {
        switch self {
        case .system: "Consommation du Mac"
        case .adapter: "Puissance du chargeur"
        case .battery: "Flux batterie"
        }
    }
}

/// What the menu bar shows.
struct MenuBarState: Equatable {
    var system: Double?
    var adapter: Double?
    var battery: Double?
    var charging: Bool
    var onAC: Bool
}

final class PowerStore: ObservableObject {
    // Published state is only refreshed while the panel is open: nothing observes it otherwise.
    @Published private(set) var snapshot = PowerSnapshot()
    @Published private(set) var history: [HistoryPoint] = []
    @Published private(set) var apps: [AppPower] = []
    @Published private(set) var appsReady = false
    @Published private(set) var ports: [PortInfo] = []
    @Published private(set) var usbDevices: [USBDeviceInfo] = []
    @Published private(set) var energyWh: Double = 0
    /// Mean power since launch (energy / time), like Stats' "Average System Total".
    @Published private(set) var averageWatts: Double?

    /// Called on the main thread every `menuBarInterval`.
    var onMenuBarUpdate: ((MenuBarState) -> Void)?
    /// Called on the main thread when the Mac has drawn more than the alert threshold for a while.
    var onSustainedLoad: ((SustainedLoad) -> Void)?

    static let idleInterval: TimeInterval = 5      // panel closed: menu bar only
    static let screensOffInterval: TimeInterval = 30  // displays asleep: nobody sees the menu bar
    static let menuBarInterval: TimeInterval = 5
    /// Above this the SMC reading is a glitch (a Mac Pro peaks around 370 W).
    static let maxPlausibleWatts: Double = 600
    private static let batteryRefreshIdle: TimeInterval = 30  // IOKit only refreshes ~every minute
    private static let batteryRefreshOpen: TimeInterval = 10

    private let queue = DispatchQueue(label: "volta.sampler", qos: .utility)
    private var timer: DispatchSourceTimer?
    private let smc = SMC.shared
    // Same IOReport channels as Stats' CPU / GPU power. Dead counters (CPU on macOS 27) fall back to the SMC.
    private let energyModel = EnergyModelReader(channels: ["CPU Energy", "GPU Energy"])
    private let processMonitor = ProcessMonitor()
    /// Its own monitor: names the app behind a sustained load while the panel is closed.
    private let alertMonitor = ProcessMonitor()
    private var loadDetector = SustainedLoadDetector()
    private var alertOnBatteryOnly = false

    // Sampler-queue state
    private var openInterval: TimeInterval = 2     // panel open: live details (user setting)
    private var historyWindow: TimeInterval = 5 * 60
    private var panelOpen = false
    private var screensAsleep = false
    /// Detail tab on screen: the apps and the ports are only sampled while their tab is shown.
    private var demand: DetailTab?
    private var tick = 0
    private var lastSample: TimeInterval?
    private var lastBatteryRead: TimeInterval = -.infinity
    private var batteryInfo: BatteryInfo?
    private var historyBuffer: [HistoryPoint] = []
    private var energyTotal = 0.0
    private var energySeconds = 0.0
    private var menuWindow: [PowerSnapshot] = []
    private var lastMenuPush: TimeInterval = -.infinity
    private var smoothedSystem: Double?
    private var lastSnapshot = PowerSnapshot()

    func start() {
        queue.async { self.schedule(interval: Self.idleInterval) }
        let nc = NSWorkspace.shared.notificationCenter
        nc.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: nil) { [weak self] _ in
            self?.queue.async { self?.didWake() }
        }
        nc.addObserver(forName: NSWorkspace.screensDidSleepNotification, object: nil, queue: nil) { [weak self] _ in
            self?.queue.async { self?.setScreensAsleep(true) }
        }
        nc.addObserver(forName: NSWorkspace.screensDidWakeNotification, object: nil, queue: nil) { [weak self] _ in
            self?.queue.async { self?.setScreensAsleep(false) }
        }
    }

    private var currentInterval: TimeInterval {
        panelOpen ? openInterval : screensAsleep ? Self.screensOffInterval : Self.idleInterval
    }

    private func setScreensAsleep(_ asleep: Bool) {
        guard asleep != screensAsleep else { return }
        screensAsleep = asleep
        schedule(interval: currentInterval)
    }

    /// After sleep, deltas span the whole night: start them over instead of integrating them.
    private func didWake() {
        lastSample = nil
        menuWindow.removeAll()
        smoothedSystem = nil
        loadDetector.reset()
        alertMonitor.reset()
        processMonitor.reset()
        if panelOpen, demand == .apps { _ = processMonitor.sample(gpuWatts: nil) }
    }

    private func schedule(interval: TimeInterval) {
        timer?.cancel()
        let t = DispatchSource.makeTimerSource(queue: queue)
        // Generous leeway lets the kernel coalesce our wakeups with other work.
        t.schedule(deadline: .now(), repeating: interval, leeway: .milliseconds(interval > 3 ? 1000 : 250))
        t.setEventHandler { [weak self] in self?.sample() }
        t.resume()
        timer = t
    }

    /// Applies the user's sampling settings (refresh rate while open, history length).
    func configure(openInterval: TimeInterval, historyMinutes: Int, sustainedAlert: Int, alertOnBatteryOnly: Bool) {
        queue.async { [self] in
            historyWindow = TimeInterval(historyMinutes * 60)
            if loadDetector.threshold != Double(sustainedAlert) {
                loadDetector.threshold = Double(sustainedAlert)
                loadDetector.reset()
            }
            self.alertOnBatteryOnly = alertOnBatteryOnly
            guard openInterval != self.openInterval else { return }
            self.openInterval = openInterval
            if panelOpen { schedule(interval: openInterval) }
        }
    }

    func setPanelOpen(_ open: Bool) {
        queue.async { [self] in
            guard open != panelOpen else { return }
            panelOpen = open
            if open {
                lastBatteryRead = -.infinity
            } else {
                demand = nil
                processMonitor.reset()
                DispatchQueue.main.async { self.appsReady = false }
            }
            schedule(interval: currentInterval)
        }
    }

    /// The detail tab now on screen (nil: none, e.g. settings page or details hidden).
    func setDemand(_ tab: DetailTab?) {
        queue.async { [self] in
            guard tab != demand else { return }
            demand = tab
            processMonitor.reset()
            DispatchQueue.main.async { self.appsReady = false }
            switch tab {
            case .apps: _ = processMonitor.sample(gpuWatts: nil)  // baseline for the first delta
            case .ports: refreshPorts()
            default: break
            }
        }
    }

    /// Restarts the energy counter (and the mean power) from now.
    func resetEnergy() {
        queue.async { [self] in
            energyTotal = 0
            energySeconds = 0
            let average = averagePower
            DispatchQueue.main.async { [self] in
                energyWh = 0
                averageWatts = average
            }
        }
    }

    // MARK: - Sampling (sampler queue)

    private func sample() {
        tick += 1
        let now = ProcessInfo.processInfo.systemUptime
        // A gap much longer than the timer period (App Nap, a stalled queue) isn't integrated: its power is unknown.
        let gap = lastSample.map { now - $0 }
        let dt = gap.map { $0 > currentInterval * 3 + 5 ? 0 : $0 } ?? currentInterval
        lastSample = now

        let batteryRefresh = panelOpen ? Self.batteryRefreshOpen : Self.batteryRefreshIdle
        if now - lastBatteryRead >= batteryRefresh {
            batteryInfo = BatteryReader.read()
            lastBatteryRead = now
        }

        var s = PowerSnapshot()
        s.batteryInfo = batteryInfo

        // Sources and fallbacks follow Stats (exelban/stats): SMC power sensors, IOReport Energy Model for the chip.
        // Battery flow from the SMC (refreshed ~every second, signed: > 0 = charging).
        if let mv = smc?.number("B0AV"), let ma = smc?.number("B0AC"), mv > 0 {
            s.battery = mv * ma / 1e6
        } else if let b = batteryInfo {
            s.battery = b.voltage * b.amperage
        }
        s.adapterIn = smc?.number("PDTR") ?? (batteryInfo?.externalConnected == true ? batteryInfo?.systemPowerIn : 0)
        // "System Total" measured by the SMC. Charger − battery also counts the charging losses,
        // so it is only a fallback (Macs without PSTR).
        if let total = smc?.number("PSTR"), total > 0, total < Self.maxPlausibleWatts {
            s.system = total
        } else if let adapter = s.adapterIn, let bat = s.battery, adapter - bat >= 0 {
            s.system = adapter - bat
        } else {
            s.system = batteryInfo?.systemLoad
        }

        let chip = energyModel?.sample() ?? [:]
        s.cpu = chip["CPU Energy"] ?? smc?.number("PP0C")
        s.gpu = chip["GPU Energy"] ?? smc?.number("PG0C")
        // Built-in display backlight: PDBR up to M4, PBwo from M5 on (Stats' sensor list).
        s.display = smc?.number("PDBR") ?? smc?.number("PBwo")
        // PHPC ("Heatpipe Power", per Asahi Linux / iSMC) covers the whole SoC package, CPU and GPU included.
        if let package = smc?.number("PHPC"), package > 0 {
            s.soc = max(0, package - (s.cpu ?? 0) - (s.gpu ?? 0))
        }
        if panelOpen, s.batteryInfo?.temperature == nil, let t = smc?.number("TB0T"), t > 0, t < 100 {
            s.batteryInfo?.temperature = t
        }

        if let sys = s.system {
            energyTotal += sys * dt / 3600
            energySeconds += dt
            historyBuffer.append(HistoryPoint(date: Date(), system: sys, cpu: s.cpu ?? 0, gpu: s.gpu ?? 0, display: s.display ?? 0, soc: s.soc ?? 0))
            // Compared as plain numbers: `Date >=` inside this closure crashes (null witness) when built with
            // Swift 6.4 for macOS 27, in 2.1 too.
            let cutoff = Date().timeIntervalSinceReferenceDate - historyWindow
            if let first = historyBuffer.firstIndex(where: { $0.date.timeIntervalSinceReferenceDate >= cutoff }), first > 0 {
                historyBuffer.removeFirst(first)
            }
        }

        lastSnapshot = s
        menuWindow.append(s)
        if now - lastMenuPush >= Self.menuBarInterval - 1.2 { pushMenuBar(now: now) }
        checkSustainedLoad(s, now: now)

        guard panelOpen else { return }
        let appsResult = demand == .apps ? processMonitor.sample(gpuWatts: s.gpu) : nil
        if demand == .ports, tick % 3 == 0 { refreshPorts() }
        let history = historyBuffer
        let energy = energyTotal
        let average = averagePower
        DispatchQueue.main.async { [self] in
            snapshot = s
            self.history = history
            energyWh = energy
            averageWatts = average
            if let appsResult {
                apps = appsResult
                appsReady = true
            }
        }
    }

    private func checkSustainedLoad(_ s: PowerSnapshot, now: TimeInterval) {
        let watts = alertOnBatteryOnly && s.onAC ? nil : s.system
        switch loadDetector.update(watts: watts, now: now) {
        case .none: break
        case .arm:
            // Baseline: the culprit is measured over the last part of the high-load window.
            alertMonitor.reset()
            _ = alertMonitor.sample(gpuWatts: nil)
        case .fire(let mean, let duration):
            let top = alertMonitor.sample(gpuWatts: s.gpu)?.first
            alertMonitor.reset()
            let load = SustainedLoad(watts: mean, duration: duration, app: top?.name, appWatts: top?.watts)
            DispatchQueue.main.async { [self] in onSustainedLoad?(load) }
        }
    }

    private var averagePower: Double? { energySeconds > 0 ? energyTotal * 3600 / energySeconds : nil }

    /// Averages the samples collected since the last push, lightly smoothed.
    private func pushMenuBar(now: TimeInterval) {
        lastMenuPush = now
        let window = menuWindow
        menuWindow.removeAll(keepingCapacity: true)
        guard let last = window.last else { return }
        func mean(_ key: (PowerSnapshot) -> Double?) -> Double? {
            let values = window.compactMap(key)
            return values.isEmpty ? nil : values.reduce(0, +) / Double(values.count)
        }
        if let sys = mean(\.system) {
            smoothedSystem = smoothedSystem.map { $0 * 0.35 + sys * 0.65 } ?? sys
        }
        let state = MenuBarState(
            system: smoothedSystem,
            adapter: mean(\.adapterIn),
            battery: mean(\.battery),
            charging: last.charging,
            onAC: (last.adapterIn ?? 0) > 0.5 || last.batteryInfo?.externalConnected == true)
        DispatchQueue.main.async { [self] in onMenuBarUpdate?(state) }
    }

    /// Pushes the buffered state to the UI right away (when the panel opens).
    func publishNow() {
        queue.async { [self] in
            let history = historyBuffer
            let energy = energyTotal
            let average = averagePower
            let last = lastSnapshot
            DispatchQueue.main.async { [self] in
                self.history = history
                energyWh = energy
                averageWatts = average
                snapshot = last
            }
        }
    }

    private func refreshPorts() {
        let p = PortsReader.ports()
        let u = PortsReader.usbDevices()
        DispatchQueue.main.async { [self] in
            if ports != p { ports = p }
            if usbDevices != u { usbDevices = u }
        }
    }
}
