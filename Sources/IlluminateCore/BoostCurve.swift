/// Maps the user's boost level onto a linear-light gain factor.
///
/// The gain multiplies SDR content in the display's extended range,
/// so SDR white (1.0) becomes `gain`. It must stay within the current
/// EDR headroom, and should stay well below it: XDR panels reach their
/// peak (1600 nit) only on a small area, while full-screen content is
/// limited to about 1000 nit sustained.
public struct BoostCurve: Equatable, Sendable {
    /// Share of the headroom used at full boost. 0.6 keeps a 1600 nit panel near 960 nit.
    public var sustainedFraction: Double
    /// Ceiling relative to the current SDR white. Without it, full boost would land at
    /// the same luminance whatever the system brightness, making that slider meaningless.
    public var maximumFactor: Double?
    /// Optional absolute ceiling for the boosted SDR white, in nits.
    public var nitsCap: Double?

    public init(sustainedFraction: Double = 0.6, maximumFactor: Double? = 2.0, nitsCap: Double? = nil) {
        self.sustainedFraction = sustainedFraction
        self.maximumFactor = maximumFactor
        self.nitsCap = nitsCap
    }

    /// The largest gain the slider may reach for the given headroom.
    ///
    /// - Parameters:
    ///   - headroom: `NSScreen.maximumExtendedDynamicRangeColorComponentValue` while EDR is engaged.
    ///   - sdrWhiteNits: current SDR white, if known; needed to apply `nitsCap`.
    public func maximumGain(headroom: Double, sdrWhiteNits: Double? = nil) -> Double {
        guard headroom > 1 else { return 1 }
        var gain = min(headroom * sustainedFraction, headroom)
        if let maximumFactor {
            gain = min(gain, maximumFactor)
        }
        if let nitsCap, let sdrWhiteNits, sdrWhiteNits > 0 {
            gain = min(gain, nitsCap / sdrWhiteNits)
        }
        return max(gain, 1)
    }

    /// Gain for a slider level in `0...1`, where 0 is no boost and 1 is `maximumGain`.
    public func gain(level: Double, maximumGain: Double) -> Double {
        let level = min(max(level, 0), 1)
        return 1 + level * (max(maximumGain, 1) - 1)
    }
}

/// Converts headroom into absolute luminance for panels with a known peak.
public struct NitsEstimate: Equatable, Sendable {
    public let sdrWhiteNits: Double

    /// Returns `nil` while EDR is not engaged, because the headroom then says nothing about SDR white.
    public init?(panelPeakNits: Double, headroom: Double) {
        guard headroom > 1.05, panelPeakNits > 0 else { return nil }
        sdrWhiteNits = panelPeakNits / headroom
    }

    public func boostedNits(gain: Double) -> Double {
        sdrWhiteNits * gain
    }
}
