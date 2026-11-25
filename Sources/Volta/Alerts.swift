import Foundation
import UserNotifications

/// A sustained high load, as reported to the user.
struct SustainedLoad: Equatable {
    var watts: Double          // mean power over the high-load window
    var duration: TimeInterval
    var app: String?           // the app drawing the most over the end of the window
    var appWatts: Double?
}

/// Detects that the Mac has drawn more than `threshold` watts for `duration` seconds.
/// Pure logic (fed with uptime timestamps), so it can be tested without sensors.
struct SustainedLoadDetector {
    enum Event: Equatable {
        case none
        /// Halfway through: time to take the baseline that will name the culprit.
        case arm
        case fire(mean: Double, duration: TimeInterval)
    }

    /// W, 0 = off.
    var threshold: Double = 0
    var duration: TimeInterval = 120
    /// No new alert before this delay, even if the load stays high.
    var cooldown: TimeInterval = 15 * 60
    /// Short dips below the threshold (down to this fraction of it) don't end a high-load window.
    var hysteresis = 0.9

    private var since: TimeInterval?
    private var sum = 0.0
    private var count = 0
    private var armed = false
    private var lastFire: TimeInterval?

    mutating func reset() {
        since = nil
        sum = 0
        count = 0
        armed = false
    }

    /// - Parameter watts: the current power, or nil when it must not be watched (unknown, or on AC with "battery only").
    mutating func update(watts: Double?, now: TimeInterval) -> Event {
        guard threshold > 0, let watts else { reset(); return .none }
        // During the cooldown nothing is tracked: the next window starts fresh (and gets its baseline).
        if let lastFire, now - lastFire < cooldown { return .none }
        if since == nil {
            guard watts >= threshold else { return .none }
            since = now
        } else if watts < threshold * hysteresis {
            reset()
            return .none
        }
        sum += watts
        count += 1
        let elapsed = now - (since ?? now)
        if elapsed >= duration {
            let mean = sum / Double(max(count, 1))
            reset()
            guard mean >= threshold else { return .none }
            lastFire = now
            return .fire(mean: mean, duration: elapsed)
        }
        if !armed, elapsed >= duration / 2 {
            armed = true
            return .arm
        }
        return .none
    }
}

enum LoadNotifier {
    /// Notifications need a real app bundle (not `swift run`).
    static var available: Bool { Bundle.main.bundleIdentifier != nil && Bundle.main.bundlePath.hasSuffix(".app") }

    static func requestAuthorization() {
        guard available else { return }
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    static func post(_ load: SustainedLoad) {
        guard available else { return }
        let content = UNMutableNotificationContent()
        content.title = L("Consommation élevée")
        content.body = body(load)
        let request = UNNotificationRequest(identifier: "volta.sustained-load", content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }

    static func body(_ load: SustainedLoad) -> String {
        let minutes = max(1, Int((load.duration / 60).rounded()))
        var text = L("%@ en moyenne depuis %d min", formatWatts(load.watts), minutes)
        if let app = load.app {
            text += " · \(app)" + (load.appWatts.map { " (\(formatWatts($0)))" } ?? "")
        }
        return text
    }
}
