import Testing
@testable import IlluminateCore

@Suite struct BoostCurveTests {
    let curve = BoostCurve()

    @Test func `no headroom means no boost`() {
        #expect(curve.maximumGain(headroom: 1.0) == 1.0)
        #expect(curve.maximumGain(headroom: 0.5) == 1.0)
    }

    @Test func `sustainable gain is a fraction of the headroom`() {
        // 500 nit SDR white on a 1600 nit panel: headroom 3.2.
        // 60 % keeps the full-screen load near the 1000 nit sustained limit (960 nit).
        #expect(abs(curve.maximumGain(headroom: 3.2) - 3.2 * 0.6) < 1e-9)
    }

    @Test func `gain is capped relative to SDR white`() {
        // Dim system brightness (~310 nit, headroom 5.158) would allow 3.1x.
        // The cap keeps the system brightness slider meaningful: boost doubles, never more.
        #expect(curve.maximumGain(headroom: 5.158) == 2.0)
        let uncapped = BoostCurve(maximumFactor: nil)
        #expect(abs(uncapped.maximumGain(headroom: 5.158) - 5.158 * 0.6) < 1e-9)
    }

    @Test func `gain never drops below 1 for small headroom`() {
        // 1.2 * 0.6 = 0.72, but a gain below 1 would darken the screen.
        #expect(curve.maximumGain(headroom: 1.2) == 1.0)
    }

    @Test func `nits cap limits the gain`() {
        let capped = BoostCurve(sustainedFraction: 1.0, maximumFactor: nil, nitsCap: 1000)
        // 500 nit SDR white, 1600 nit peak: headroom 3.2, cap allows 2x.
        let gain = capped.maximumGain(headroom: 3.2, sdrWhiteNits: 500)
        #expect(abs(gain - 2.0) < 1e-9)
    }

    @Test(arguments: [(0.0, 1.0), (0.5, 1.5), (1.0, 2.0)])
    func `level maps linearly onto gain`(level: Double, expected: Double) {
        #expect(abs(curve.gain(level: level, maximumGain: 2.0) - expected) < 1e-9)
    }

    @Test(arguments: [(-0.5, 1.0), (1.5, 2.0)])
    func `level is clamped to the slider range`(level: Double, expected: Double) {
        #expect(curve.gain(level: level, maximumGain: 2.0) == expected)
    }
}

@Suite struct NitsEstimateTests {
    @Test func `sdr white follows from panel peak and headroom`() throws {
        let estimate = try #require(NitsEstimate(panelPeakNits: 1600, headroom: 3.2))
        #expect(abs(estimate.sdrWhiteNits - 500) < 1e-9)
        #expect(abs(estimate.boostedNits(gain: 1.92) - 960) < 1e-9)
    }

    @Test func `no estimate without engaged headroom`() {
        #expect(NitsEstimate(panelPeakNits: 1600, headroom: 1.0) == nil)
    }

    @Test func `headroom must clear the engagement threshold`() {
        // Below 1.05 the headroom is noise around SDR, not a reading of SDR white.
        #expect(NitsEstimate(panelPeakNits: 1600, headroom: 1.05) == nil)
        #expect(NitsEstimate(panelPeakNits: 1600, headroom: 1.06) != nil)
    }

    @Test func `unknown panel peak gives no estimate`() {
        #expect(NitsEstimate(panelPeakNits: 0, headroom: 3.2) == nil)
    }
}
