/// How the boost is produced.
public enum BoostTechniqueKind: String, Codable, Sendable, CaseIterable {
    /// Full-screen EDR multiply overlay. Keeps HDR video intact and leaves
    /// no system state behind if the app dies. Default.
    case overlay
    /// EDR trigger plus a scaled gamma table. Colour-faithful, but clips HDR
    /// video and fights other gamma apps such as f.lux.
    case gamma
}

/// User settings. A value type so that every change is one atomic write.
public struct Preferences: Equatable, Sendable {
    public var isEnabled = true
    /// Boost level in `0...1`; mapped to a gain by `BoostCurve`.
    public var level = 0.6 {
        didSet { level = min(max(level, 0), 1) }
    }
    public var technique = BoostTechniqueKind.overlay
    /// Pause on battery below this percentage. `nil` disables the rule.
    public var batteryThreshold: Int? = 20
    public var pauseInLowPowerMode = true
    /// Drop to no boost while a player keeps the display awake, so HDR highlights
    /// are not multiplied past the panel's range. The overlay stays up to keep headroom.
    public var reduceDuringPlayback = true

    public init() {}
}

extension Preferences: Codable {
    private enum CodingKeys: String, CodingKey {
        case isEnabled, level, technique, batteryThreshold, pauseInLowPowerMode, reduceDuringPlayback
    }

    /// Decodes leniently: each missing or unknown value keeps its default,
    /// so an update never wipes the user's other settings.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let defaults = Preferences()
        isEnabled = (try? container.decode(Bool.self, forKey: .isEnabled)) ?? defaults.isEnabled
        level = min(max((try? container.decode(Double.self, forKey: .level)) ?? defaults.level, 0), 1)
        technique = (try? container.decode(BoostTechniqueKind.self, forKey: .technique)) ?? defaults.technique
        // An explicit `null` means "rule disabled"; an absent or malformed value keeps the default.
        batteryThreshold = (try? container.decodeNil(forKey: .batteryThreshold)) == true
            ? nil
            : (try? container.decode(Int.self, forKey: .batteryThreshold)) ?? defaults.batteryThreshold
        pauseInLowPowerMode = (try? container.decode(Bool.self, forKey: .pauseInLowPowerMode)) ?? defaults.pauseInLowPowerMode
        reduceDuringPlayback = (try? container.decode(Bool.self, forKey: .reduceDuringPlayback)) ?? defaults.reduceDuringPlayback
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(isEnabled, forKey: .isEnabled)
        try container.encode(level, forKey: .level)
        try container.encode(technique, forKey: .technique)
        try container.encode(batteryThreshold, forKey: .batteryThreshold)
        try container.encode(pauseInLowPowerMode, forKey: .pauseInLowPowerMode)
        try container.encode(reduceDuringPlayback, forKey: .reduceDuringPlayback)
    }
}

/// A snapshot of the power source, decoupled from IOKit for testing.
public struct PowerStatus: Equatable, Sendable {
    public var isOnBattery: Bool
    /// `nil` on machines without a battery.
    public var batteryPercent: Int?
    public var isLowPowerMode: Bool

    public init(isOnBattery: Bool, batteryPercent: Int?, isLowPowerMode: Bool) {
        self.isOnBattery = isOnBattery
        self.batteryPercent = batteryPercent
        self.isLowPowerMode = isLowPowerMode
    }

    public func suspensionReasons(for preferences: Preferences) -> Set<SuspensionReason> {
        var reasons: Set<SuspensionReason> = []
        if isOnBattery, let threshold = preferences.batteryThreshold,
           let batteryPercent, batteryPercent < threshold {
            reasons.insert(.lowBattery)
        }
        if isLowPowerMode, preferences.pauseInLowPowerMode {
            reasons.insert(.lowPowerMode)
        }
        return reasons
    }
}
