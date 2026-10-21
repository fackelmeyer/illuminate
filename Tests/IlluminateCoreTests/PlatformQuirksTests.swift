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

    @Test func `inactive display assertions are not playback`() {
        let assertions = [DisplayAssertion(processName: "Safari", type: "PreventUserIdleDisplaySleep", isActive: false)]
        #expect(policy.isPlaybackLikely(assertions) == false)
    }
}

@Suite struct PlaybackStateTests {
    let now = ContinuousClock.now

    @Test func `short playback signals do not dim the display`() {
        var state = PlaybackState()
        state.observe(true, at: now)
        state.observe(true, at: now + .seconds(2))
        #expect(state.isPlaybackLikely == false)
        state.observe(false, at: now + .seconds(4))
        state.observe(true, at: now + .seconds(6))
        state.observe(true, at: now + .seconds(8))
        #expect(state.isPlaybackLikely == false)
        state.observe(true, at: now + .seconds(10))
        #expect(state.isPlaybackLikely)
    }

    @Test func `app switching gaps do not restore the boost`() {
        var state = PlaybackState()
        state.observe(true, at: now)
        state.observe(true, at: now + .seconds(4))
        #expect(state.isPlaybackLikely)

        state.observe(false, at: now + .seconds(6))
        state.observe(false, at: now + .seconds(14))
        #expect(state.isPlaybackLikely)
        state.observe(true, at: now + .seconds(16))
        state.observe(false, at: now + .seconds(18))
        state.observe(false, at: now + .seconds(26))
        #expect(state.isPlaybackLikely)
        state.observe(false, at: now + .seconds(28))
        #expect(state.isPlaybackLikely == false)
    }

    @Test(arguments: [false, true])
    func `failed queries preserve state and restart confirmation`(playing: Bool) {
        var state = PlaybackState()
        state.observe(playing, at: now)
        state.observe(playing, at: now + .seconds(4))
        #expect(state.isPlaybackLikely == playing)

        state.observe(!playing, at: now + .seconds(6))
        state.observe(nil, at: now + .seconds(8))
        state.observe(!playing, at: now + .seconds(20))
        #expect(state.isPlaybackLikely == playing)
        state.observe(!playing, at: now + .seconds(30))
        #expect(state.isPlaybackLikely == !playing)
    }

    @Test func `a new monitoring session forgets pending and confirmed playback`() {
        var state = PlaybackState()
        state.observe(true, at: now)
        state.observe(true, at: now + .seconds(4))
        state = PlaybackState()
        state.observe(true, at: now + .seconds(20))
        #expect(state.isPlaybackLikely == false)
    }
}

@Suite struct PlaybackDimmingTests {
    let now = ContinuousClock.now

    @Test func `playback fades down and back up instead of jumping`() {
        var dimming = PlaybackDimming()
        #expect(dimming.factor(at: now) == 1)
        dimming.setReduced(true, at: now)
        #expect(dimming.factor(at: now) == 1)
        #expect(dimming.factor(at: now + .milliseconds(500)) == 0.5)
        #expect(dimming.factor(at: now + .seconds(1)) == 0)

        dimming.setReduced(false, at: now + .seconds(2))
        #expect(dimming.factor(at: now + .seconds(2)) == 0)
        #expect(dimming.factor(at: now + .milliseconds(2500)) == 0.5)
        #expect(dimming.factor(at: now + .seconds(3)) == 1)
        #expect(dimming.factor(at: now + .seconds(30)) == 1)
    }

    @Test func `repeated ticks do not restart a fade`() {
        var dimming = PlaybackDimming()
        dimming.setReduced(true, at: now)
        dimming.setReduced(true, at: now + .milliseconds(500))
        #expect(dimming.factor(at: now + .seconds(1)) == 0)
    }

    @Test func `disabling the playback rule midway continues from the current brightness`() {
        var dimming = PlaybackDimming()
        dimming.setReduced(true, at: now)
        dimming.setReduced(false, at: now + .milliseconds(500))
        #expect(dimming.factor(at: now + .milliseconds(500)) == 0.5)
        #expect(dimming.factor(at: now + .seconds(1)) == 0.75)
        #expect(dimming.factor(at: now + .milliseconds(1500)) == 1)
    }

    @Test func `a playback fade never exceeds live EDR headroom`() {
        var dimming = PlaybackDimming()
        dimming.setReduced(true, at: now)
        let level = 0.8 * dimming.factor(at: now + .milliseconds(500))
        #expect(BoostCurve().targetGain(level: level, headroom: 3) > 1)
        #expect(BoostCurve().targetGain(level: level, headroom: 1) == 1)
    }
}
