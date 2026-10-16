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

    @Test(arguments: [(1.2, 1.0), (-0.3, 0.0), (0.7, 0.7)])
    func `level is clamped on assignment`(assigned: Double, expected: Double) {
        // The hotkeys step the level by ±0.1 and rely on this clamp at both ends.
        var preferences = Preferences()
        preferences.level = assigned
        #expect(preferences.level == expected)
    }

    @Test func `explicit null disables the battery rule`() throws {
        let data = Data(#"{"batteryThreshold": null}"#.utf8)
        #expect(try JSONDecoder().decode(Preferences.self, from: data).batteryThreshold == nil)
    }

    @Test func `malformed battery threshold falls back to the default`() throws {
        let data = Data(#"{"batteryThreshold": "twenty"}"#.utf8)
        #expect(try JSONDecoder().decode(Preferences.self, from: data).batteryThreshold == Preferences().batteryThreshold)
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
