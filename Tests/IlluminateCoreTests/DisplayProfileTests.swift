import Testing
@testable import IlluminateCore

@Suite struct DisplayProfileTests {
    @Test func `built-in XDR panel is eligible with a known peak`() {
        let profile = DisplayProfile(name: "Built-in Retina Display", isBuiltin: true, potentialHeadroom: 16)
        #expect(profile.isEligible)
        #expect(profile.panelPeakNits == 1600)
    }

    @Test func `display without potential headroom is not eligible`() {
        let air = DisplayProfile(name: "Built-in Retina Display", isBuiltin: true, potentialHeadroom: 1)
        #expect(air.isEligible == false)
        #expect(air.panelPeakNits == nil)
    }

    @Test func `marginal headroom is not eligible`() {
        // The 2022 Studio Display reports a little headroom but cannot sustain a boost.
        let studio = DisplayProfile(name: "Studio Display", isBuiltin: false, potentialHeadroom: 1.3)
        #expect(studio.isEligible == false)
    }

    @Test(arguments: [("Pro Display XDR", 1600.0), ("Studio Display XDR", 2000.0)])
    func `known Apple externals have a peak`(name: String, peak: Double) {
        let profile = DisplayProfile(name: name, isBuiltin: false, potentialHeadroom: 8)
        #expect(profile.isEligible)
        #expect(profile.panelPeakNits == peak)
    }

    @Test func `unknown HDR monitor is eligible without a peak`() {
        let profile = DisplayProfile(name: "LG UltraFine", isBuiltin: false, potentialHeadroom: 4)
        #expect(profile.isEligible)
        #expect(profile.panelPeakNits == nil)
    }
}
