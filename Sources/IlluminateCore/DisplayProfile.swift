import Foundation

/// What we know about a display before engaging it.
///
/// Eligibility comes from the runtime-reported potential headroom rather
/// than a model allowlist, so new XDR hardware works without an update.
public struct DisplayProfile: Equatable, Sendable {
    /// Below this potential headroom a boost is not worth the battery and heat.
    public static let minimumPotentialHeadroom = 2.0

    public let name: String
    public let isBuiltin: Bool
    /// `NSScreen.maximumPotentialExtendedDynamicRangeColorComponentValue`.
    public let potentialHeadroom: Double

    public init(name: String, isBuiltin: Bool, potentialHeadroom: Double) {
        self.name = name
        self.isBuiltin = isBuiltin
        self.potentialHeadroom = potentialHeadroom
    }

    public var isEligible: Bool {
        potentialHeadroom >= Self.minimumPotentialHeadroom
    }

    /// Peak luminance from Apple's tech specs, where the panel is identifiable.
    public var panelPeakNits: Double? {
        guard isEligible else { return nil }
        if isBuiltin { return 1600 }   // Every built-in Liquid Retina XDR panel peaks at 1600 nit.
        if name.localizedStandardContains("Studio Display XDR") { return 2000 }
        if name.localizedStandardContains("Pro Display XDR") { return 1600 }
        return nil
    }
}
