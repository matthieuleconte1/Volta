import Foundation
import Testing
@testable import Volta

@Suite struct SMCDecoding {
    @Test func float() {
        let bytes = withUnsafeBytes(of: Float(12.5)) { Array($0) }
        #expect(SMC.decode(type: "flt ", bytes: bytes, littleEndian: true) == 12.5)
    }

    @Test func nonFiniteFloatIsDropped() {
        let bytes = withUnsafeBytes(of: Float.nan) { Array($0) }
        #expect(SMC.decode(type: "flt ", bytes: bytes, littleEndian: true) == nil)
    }

    @Test func unsignedLittleEndian() {
        #expect(SMC.decode(type: "ui16", bytes: [0x34, 0x12], littleEndian: true) == 0x1234)
        #expect(SMC.decode(type: "ui32", bytes: [0x01, 0, 0, 0], littleEndian: true) == 1)
        #expect(SMC.decode(type: "ui8 ", bytes: [200], littleEndian: true) == 200)
    }

    @Test func unsignedBigEndian() {
        #expect(SMC.decode(type: "ui16", bytes: [0x12, 0x34], littleEndian: false) == 0x1234)
    }

    @Test func signed() {
        #expect(SMC.decode(type: "si8 ", bytes: [0xFF], littleEndian: true) == -1)
        #expect(SMC.decode(type: "si16", bytes: [0x18, 0xFC], littleEndian: true) == -1000)
        #expect(SMC.decode(type: "si32", bytes: [0xFE, 0xFF, 0xFF, 0xFF], littleEndian: true) == -2)
    }

    @Test func fixedPoint() {
        #expect(SMC.decode(type: "sp78", bytes: [0x28, 0x80], littleEndian: true) == 40.5)
        #expect(SMC.decode(type: "fpe2", bytes: [0x00, 0x0A], littleEndian: true) == 2.5)
    }

    @Test func shortOrUnknown() {
        #expect(SMC.decode(type: "ui32", bytes: [1, 2], littleEndian: true) == nil)
        #expect(SMC.decode(type: "flag", bytes: [1], littleEndian: true) == nil)
    }
}

@Suite struct Formatting {
    @Test func menuBar() {
        #expect(AppDelegate.menuBarText(nil, signed: false) == "– W")
        #expect(AppDelegate.menuBarText(8.42, signed: false) == "8.4 W")
        #expect(AppDelegate.menuBarText(12.4, signed: false) == "12 W")
        #expect(AppDelegate.menuBarText(9.96, signed: false) == "10 W")
        #expect(AppDelegate.menuBarText(3, signed: true) == "+3.0 W")
        #expect(AppDelegate.menuBarText(-3, signed: true) == "-3.0 W")
    }

    @Test func watts() {
        #expect(formatWatts(nil) == "–")
        #expect(formatWatts(0.001) == "0 W")
        #expect(formatWatts(0.456) == "0.46 W")
        #expect(formatWatts(5.25) == "5.2 W" || formatWatts(5.25) == "5.3 W")
        #expect(formatWatts(123.4) == "123 W")
        #expect(formatWatts(2, signed: true) == "+2.0 W")
    }
}

@Suite struct NightHours {
    @Test func acrossMidnight() {
        #expect(AppSettings.isNightHour(22, start: 21, end: 7))
        #expect(AppSettings.isNightHour(0, start: 21, end: 7))
        #expect(AppSettings.isNightHour(6, start: 21, end: 7))
        #expect(!AppSettings.isNightHour(7, start: 21, end: 7))
        #expect(!AppSettings.isNightHour(20, start: 21, end: 7))
    }

    @Test func sameDay() {
        #expect(AppSettings.isNightHour(13, start: 13, end: 15))
        #expect(!AppSettings.isNightHour(15, start: 13, end: 15))
    }

    @Test func equalHoursMeanNoNight() {
        #expect(!AppSettings.isNightHour(9, start: 9, end: 9))
    }
}

@Suite struct Versions {
    @Test func comparison() {
        #expect(AppVersion.isNewer("v2.2.0", than: "2.1.0"))
        #expect(AppVersion.isNewer("2.10", than: "2.9.9"))
        #expect(!AppVersion.isNewer("v2.1.0", than: "2.1.0"))
        #expect(!AppVersion.isNewer("2.1", than: "2.1.0"))
        #expect(!AppVersion.isNewer("2.0.9", than: "2.1"))
    }

    @Test func parseRelease() throws {
        let json = #"{"tag_name": "v2.3.0", "html_url": "https://github.com/x/y/releases/tag/v2.3.0"}"#
        let state = UpdateChecker.parse(data: Data(json.utf8), status: 200, current: "2.2.0")
        #expect(state == .available(version: "2.3.0", url: URL(string: "https://github.com/x/y/releases/tag/v2.3.0")!))
        #expect(UpdateChecker.parse(data: Data(json.utf8), status: 200, current: "2.3.0") == .upToDate)
        #expect(UpdateChecker.parse(data: nil, status: 404) == .failed)
        #expect(UpdateChecker.parse(data: Data("nope".utf8), status: 200) == .failed)
    }
}

@Suite struct SustainedLoadDetection {
    private func detector(threshold: Double = 20) -> SustainedLoadDetector {
        var d = SustainedLoadDetector()
        d.threshold = threshold
        d.duration = 120
        d.cooldown = 900
        return d
    }

    /// Feeds `watts` every `step` seconds from `start` for `seconds`, returning the non-empty events.
    private func feed(_ d: inout SustainedLoadDetector, watts: Double, from start: Double, for seconds: Double,
                      step: Double = 5) -> [(Double, SustainedLoadDetector.Event)] {
        var events: [(Double, SustainedLoadDetector.Event)] = []
        var t = start
        while t <= start + seconds {
            let e = d.update(watts: watts, now: t)
            if e != .none { events.append((t, e)) }
            t += step
        }
        return events
    }

    @Test func armsThenFires() {
        var d = detector()
        let events = feed(&d, watts: 30, from: 0, for: 125)
        #expect(events.count == 2)
        #expect(events.first?.1 == .arm)
        #expect(events.first?.0 == 60)
        #expect(events.last?.1 == .fire(mean: 30, duration: 120))
    }

    @Test func offWhenThresholdIsZero() {
        var d = detector(threshold: 0)
        #expect(feed(&d, watts: 100, from: 0, for: 300).isEmpty)
    }

    @Test func lowLoadNeverFires() {
        var d = detector()
        #expect(feed(&d, watts: 12, from: 0, for: 600).isEmpty)
    }

    @Test func aDropEndsTheWindow() {
        var d = detector()
        _ = feed(&d, watts: 30, from: 0, for: 100)
        #expect(d.update(watts: 10, now: 105) == .none)
        // A new window starts from scratch: no alert 20 s later.
        #expect(feed(&d, watts: 30, from: 110, for: 20).allSatisfy { $0.1 != .fire(mean: 30, duration: 120) })
    }

    @Test func shortDipWithinHysteresisKeepsTheWindow() {
        var d = detector()
        _ = feed(&d, watts: 30, from: 0, for: 60)
        #expect(d.update(watts: 19, now: 65) == .none)  // 19 ≥ 20 × 0.9
        let events = feed(&d, watts: 30, from: 70, for: 50)
        #expect(events.contains { if case .fire = $0.1 { true } else { false } })
    }

    @Test func nilWattsResets() {
        var d = detector()
        _ = feed(&d, watts: 30, from: 0, for: 100)
        #expect(d.update(watts: nil, now: 105) == .none)
        #expect(feed(&d, watts: 30, from: 110, for: 30).allSatisfy { $0.1 != .fire(mean: 30, duration: 120) })
    }

    @Test func cooldownThenNewAlert() {
        var d = detector()
        _ = feed(&d, watts: 30, from: 0, for: 125)
        // Still high, but within the cooldown: silent.
        #expect(feed(&d, watts: 30, from: 130, for: 700).isEmpty)
        // After the cooldown, a fresh window arms and fires again.
        let events = feed(&d, watts: 30, from: 1025, for: 125)
        #expect(events.map(\.1).first == .arm)
        #expect(events.contains { if case .fire = $0.1 { true } else { false } })
    }
}

@Suite(.serialized) struct Notifications {
    @Test func english() {
        let saved = Localization.english
        defer { Localization.english = saved }
        Localization.english = true
        let text = LoadNotifier.body(SustainedLoad(watts: 28, duration: 120, app: "Safari", appWatts: 16.4))
        #expect(text == "28.0 W on average for 2 min · Safari (16.4 W)")
        #expect(L("Batterie %d %%", 37) == "Battery 37 %")
        #expect(L("Texte sans traduction") == "Texte sans traduction")
    }

    @Test func body() {
        let saved = Localization.english
        defer { Localization.english = saved }
        Localization.english = false
        let text = LoadNotifier.body(SustainedLoad(watts: 28, duration: 120, app: "Safari", appWatts: 16.4))
        #expect(text == "28.0 W en moyenne depuis 2 min · Safari (16.4 W)")
        #expect(LoadNotifier.body(SustainedLoad(watts: 28, duration: 120)) == "28.0 W en moyenne depuis 2 min")
    }
}
