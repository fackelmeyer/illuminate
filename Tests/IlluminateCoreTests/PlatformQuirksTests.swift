import Testing
@testable import IlluminateCore

@Suite struct GammaCompatibilityTests {
    @Test(arguments: ["Apple M5 Pro", "Apple M5 Max"])
    func `M5 Pro and Max ignore gamma tables`(brand: String) {
        // FB22273730: CGSetDisplayTransferByTable succeeds and reads back, but has no visible effect.
        #expect(GammaCompatibility(cpuBrand: brand).isGammaBroken)
    }

    @Test(arguments: ["Apple M1 Max", "Apple M2 Pro", "Apple M5", "Apple M4 Max", "Apple M15 Pro"])
    func `other chips are fine`(brand: String) {
        #expect(GammaCompatibility(cpuBrand: brand).isGammaBroken == false)
    }
}

@Suite struct PlaybackPolicyTests {
    let policy = PlaybackPolicy()

    @Test func `a browser keeping the display awake counts as playback`() {
        let assertions = [DisplayAssertion(processName: "Safari", type: "PreventUserIdleDisplaySleep")]
        #expect(policy.isPlaybackLikely(assertions))
    }

    @Test func `legacy assertion name counts too`() {
        let assertions = [DisplayAssertion(processName: "IINA", type: "NoDisplaySleepAssertion")]
        #expect(policy.isPlaybackLikely(assertions))
    }

    @Test(arguments: ["WindowServer", "powerd", "coreaudiod", "caffeinate", "Amphetamine", "Illuminate"])
    func `system and keep-awake tools are ignored`(process: String) {
        let assertions = [DisplayAssertion(processName: process, type: "PreventUserIdleDisplaySleep")]
        #expect(policy.isPlaybackLikely(assertions) == false)
    }

    @Test func `system sleep assertions are not playback`() {
        let assertions = [DisplayAssertion(processName: "Music", type: "PreventUserIdleSystemSleep")]
        #expect(policy.isPlaybackLikely(assertions) == false)
    }

    @Test func `no assertions, no playback`() {
        #expect(policy.isPlaybackLikely([]) == false)
    }
}
