/// A display transfer table as read by `CGGetDisplayTransferByTable`.
///
/// The boost scales the *captured* table instead of writing a fresh ramp,
/// so the user's ColorSync profile and calibration survive.
public struct GammaTable: Equatable, Sendable {
    public var red: [Float]
    public var green: [Float]
    public var blue: [Float]

    public init(red: [Float], green: [Float], blue: [Float]) {
        precondition(red.count == green.count && green.count == blue.count, "Channel lengths differ")
        self.red = red
        self.green = green
        self.blue = blue
    }

    public static func identity(count: Int) -> GammaTable {
        precondition(count >= 2, "A ramp needs at least two entries")
        let ramp = (0..<count).map { Float($0) / Float(count - 1) }
        return GammaTable(red: ramp, green: ramp, blue: ramp)
    }

    public var count: Int { red.count }

    /// Multiplies every channel by `gain`. Values above 1 are intentional:
    /// with EDR engaged the pipeline passes them through instead of clipping.
    public func scaled(by gain: Float) -> GammaTable {
        GammaTable(
            red: red.map { $0 * gain },
            green: green.map { $0 * gain },
            blue: blue.map { $0 * gain }
        )
    }

    /// Caps every value at `upper`. `CGGetDisplayTransferByTable` reports boosted values
    /// as 1, so drift detection must compare against the clamped table.
    public func clamped(to upper: Float) -> GammaTable {
        GammaTable(
            red: red.map { min($0, upper) },
            green: green.map { min($0, upper) },
            blue: blue.map { min($0, upper) }
        )
    }

    /// True for the all-black table that `CGDisplayRestoreColorSyncSettings` occasionally leaves behind.
    public var isDegenerate: Bool {
        let peak = max(red.max() ?? 0, green.max() ?? 0, blue.max() ?? 0)
        return peak < 0.01
    }

    public func isApproximatelyEqual(to other: GammaTable, tolerance: Float = 1e-3) -> Bool {
        guard count == other.count else { return false }
        func close(_ a: [Float], _ b: [Float]) -> Bool {
            zip(a, b).allSatisfy { abs($0 - $1) <= tolerance }
        }
        return close(red, other.red) && close(green, other.green) && close(blue, other.blue)
    }
}
