import Testing
@testable import IlluminateCore

@Suite struct GammaTableTests {
    let identity = GammaTable.identity(count: 256)

    @Test func `identity ramps from 0 to 1`() {
        #expect(identity.red.first == 0)
        #expect(identity.red.last == 1)
        #expect(identity.count == 256)
    }

    @Test func `scaling multiplies every channel without clamping`() {
        let scaled = identity.scaled(by: 2)
        #expect(scaled.red.last == 2)
        #expect(scaled.green.last == 2)
        #expect(scaled.blue[128] == identity.blue[128] * 2)
    }

    @Test func `scaling preserves a calibrated curve shape`() {
        let calibrated = GammaTable(red: [0, 0.4, 0.9], green: [0, 0.5, 1], blue: [0, 0.3, 0.8])
        let scaled = calibrated.scaled(by: 1.5)
        #expect(scaled.red == [0, 0.4 * 1.5, 0.9 * 1.5])
        #expect(scaled.blue == [0, 0.3 * 1.5, 0.8 * 1.5])
    }

    @Test func `gain of 1 is the identity`() {
        #expect(identity.scaled(by: 1) == identity)
    }

    @Test func `all-zero table is degenerate`() {
        // CGDisplayRestoreColorSyncSettings occasionally zeroes the table (black screen).
        let zero = GammaTable(red: [0, 0, 0], green: [0, 0, 0], blue: [0, 0, 0])
        #expect(zero.isDegenerate)
        #expect(identity.isDegenerate == false)
    }

    @Test func `approximate equality tolerates float round-trips`() {
        var nudged = identity
        nudged.red[10] += 1e-5
        #expect(identity.isApproximatelyEqual(to: nudged))
        nudged.red[10] += 0.01
        #expect(identity.isApproximatelyEqual(to: nudged) == false)
    }

    @Test func `clamping caps values at the readback limit`() {
        // CGGetDisplayTransferByTable reports values above 1 as 1, even while they are in effect.
        let boosted = identity.scaled(by: 1.92)
        let clamped = boosted.clamped(to: 1)
        #expect(clamped.red.last == 1)
        #expect(clamped.green[128] == boosted.green[128])
        #expect(clamped.red.max() == 1)
    }

    @Test func `tables of different length are not equal`() {
        #expect(identity.isApproximatelyEqual(to: .identity(count: 128)) == false)
    }

    @Test func `a valid reading becomes the baseline`() {
        let calibrated = identity.scaled(by: 0.9)
        #expect(GammaTable.baseline(reading: calibrated, previous: identity) == calibrated)
    }

    @Test func `a black reading keeps the previous baseline`() {
        // The previous baseline still holds the user's calibration; a linear ramp would lose it.
        let calibrated = identity.scaled(by: 0.9)
        let black = identity.scaled(by: 0)
        #expect(GammaTable.baseline(reading: black, previous: calibrated) == calibrated)
    }

    @Test func `a black reading without a previous baseline falls back to identity`() {
        let black = identity.scaled(by: 0)
        #expect(GammaTable.baseline(reading: black, previous: nil) == identity)
    }
}
