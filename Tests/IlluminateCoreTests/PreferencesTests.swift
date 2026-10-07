import Foundation
import Testing
@testable import IlluminateCore

@Suite struct PreferencesTests {
    @Test func `round-trips through JSON`() throws {
        var preferences = Preferences()
        preferences.isEnabled = false
        preferences.level = 0.3
        preferences.technique = .gamma
        preferences.batteryThreshold = nil
        preferences.reduceDuringPlayback = false
        let data = try JSONEncoder().encode(preferences)
        #expect(try JSONDecoder().decode(Preferences.self, from: data) == preferences)
    }

    @Test func `missing keys fall back to defaults`() throws {
        // Older versions stored fewer keys; decoding must not reset everything.
        let data = Data(#"{"level": 0.25}"#.utf8)
        let decoded = try JSONDecoder().decode(Preferences.self, from: data)
        #expect(decoded.level == 0.25)
        #expect(decoded.technique == Preferences().technique)
        #expect(decoded.batteryThreshold == Preferences().batteryThreshold)
        #expect(decoded.reduceDuringPlayback == Preferences().reduceDuringPlayback)
    }

    @Test func `level is clamped on decode`() throws {
        let data = Data(#"{"level": 7}"#.utf8)
        #expect(try JSONDecoder().decode(Preferences.self, from: data).level == 1)
    }

    @Test func `unknown technique falls back to overlay`() throws {
        let data = Data(#"{"technique": "native"}"#.utf8)
        #expect(try JSONDecoder().decode(Preferences.self, from: data).technique == .overlay)
    }
}

@Suite struct PowerPolicyTests {
    let preferences = Preferences()   // threshold 20 %, pause in Low Power Mode

    @Test func `plugged in never pauses for battery`() {
        let power = PowerStatus(isOnBattery: false, batteryPercent: 5, isLowPowerMode: false)
        #expect(power.suspensionReasons(for: preferences).isEmpty)
    }

    @Test func `on battery below threshold pauses`() {
        let power = PowerStatus(isOnBattery: true, batteryPercent: 19, isLowPowerMode: false)
        #expect(power.suspensionReasons(for: preferences) == [.lowBattery])
    }

    @Test func `at threshold keeps boosting`() {
        let power = PowerStatus(isOnBattery: true, batteryPercent: 20, isLowPowerMode: false)
        #expect(power.suspensionReasons(for: preferences).isEmpty)
    }

    @Test func `disabled threshold never pauses for battery`() {
        var preferences = preferences
        preferences.batteryThreshold = nil
        let power = PowerStatus(isOnBattery: true, batteryPercent: 3, isLowPowerMode: false)
        #expect(power.suspensionReasons(for: preferences).isEmpty)
    }

    @Test func `low power mode pauses when enabled`() {
        let power = PowerStatus(isOnBattery: false, batteryPercent: nil, isLowPowerMode: true)
        #expect(power.suspensionReasons(for: preferences) == [.lowPowerMode])
        var relaxed = preferences
        relaxed.pauseInLowPowerMode = false
        #expect(power.suspensionReasons(for: relaxed).isEmpty)
    }
}
