import Foundation
import Testing
@testable import IlluminateCore

@Suite struct EngagementMachineTests {
    let t0 = Date(timeIntervalSinceReferenceDate: 0)
    let config = EngagementMachine.Configuration(
        readyThreshold: 1.05, timeout: 25, cooldown: 30, maximumFailures: 3
    )

    @Test func `starts idle`() {
        let machine = EngagementMachine(configuration: config)
        #expect(machine.phase == .idle)
    }

    @Test func `start begins engaging`() {
        var machine = EngagementMachine(configuration: config)
        machine.start(at: t0)
        #expect(machine.phase == .engaging(since: t0))
    }

    @Test func `headroom above threshold makes it ready`() {
        var machine = EngagementMachine(configuration: config)
        machine.start(at: t0)
        machine.observe(headroom: 1.02, at: t0 + 1)
        #expect(machine.phase == .engaging(since: t0))
        machine.observe(headroom: 2.6, at: t0 + 2)
        #expect(machine.phase == .ready)
    }

    @Test func `timeout moves to cooldown`() {
        var machine = EngagementMachine(configuration: config)
        machine.start(at: t0)
        machine.observe(headroom: 1.0, at: t0 + 26)
        #expect(machine.phase == .cooldown(until: t0 + 26 + 30))
        #expect(machine.failures == 1)
    }

    @Test func `cooldown retries after it expires`() {
        var machine = EngagementMachine(configuration: config)
        machine.start(at: t0)
        machine.observe(headroom: 1.0, at: t0 + 26)
        machine.observe(headroom: 1.0, at: t0 + 40)
        #expect(machine.phase == .cooldown(until: t0 + 56))
        machine.observe(headroom: 1.0, at: t0 + 57)
        #expect(machine.phase == .engaging(since: t0 + 57))
    }

    @Test func `repeated failures isolate the display`() {
        var machine = EngagementMachine(configuration: config)
        var now = t0
        machine.start(at: now)
        for _ in 0..<3 {
            now += 26
            machine.observe(headroom: 1.0, at: now)   // timeout -> cooldown
            now += 31
            machine.observe(headroom: 1.0, at: now)   // cooldown over -> engaging
        }
        #expect(machine.phase == .isolated)
    }

    @Test func `success resets the failure count`() {
        var machine = EngagementMachine(configuration: config)
        machine.start(at: t0)
        machine.observe(headroom: 1.0, at: t0 + 26)
        machine.observe(headroom: 1.0, at: t0 + 57)
        machine.observe(headroom: 3.0, at: t0 + 58)
        #expect(machine.phase == .ready)
        #expect(machine.failures == 0)
    }

    @Test func `losing headroom while ready re-engages`() {
        // WindowServer withdraws headroom ~15 s after the EDR surface is hidden.
        var machine = EngagementMachine(configuration: config)
        machine.start(at: t0)
        machine.observe(headroom: 3.0, at: t0 + 1)
        machine.observe(headroom: 1.0, at: t0 + 100)
        #expect(machine.phase == .engaging(since: t0 + 100))
    }

    @Test func `stop returns to idle and forgets failures`() {
        var machine = EngagementMachine(configuration: config)
        machine.start(at: t0)
        machine.observe(headroom: 1.0, at: t0 + 26)
        machine.stop()
        #expect(machine.phase == .idle)
        #expect(machine.failures == 0)
    }

    @Test func `observations while idle are ignored`() {
        var machine = EngagementMachine(configuration: config)
        machine.observe(headroom: 3.0, at: t0)
        #expect(machine.phase == .idle)
    }

    @Test func `isolated recovers when headroom appears`() {
        // e.g. another app shows HDR content and WindowServer grants headroom after all.
        var machine = EngagementMachine(configuration: config)
        var now = t0
        machine.start(at: now)
        for _ in 0..<3 {
            now += 26; machine.observe(headroom: 1.0, at: now)
            now += 31; machine.observe(headroom: 1.0, at: now)
        }
        #expect(machine.phase == .isolated)
        machine.observe(headroom: 1.0, at: now + 100)
        #expect(machine.phase == .isolated)
        machine.observe(headroom: 3.0, at: now + 101)
        #expect(machine.phase == .ready)
        #expect(machine.failures == 0)
    }

    @Test func `headroom during cooldown makes it ready`() {
        var machine = EngagementMachine(configuration: config)
        machine.start(at: t0)
        machine.observe(headroom: 1.0, at: t0 + 26)
        machine.observe(headroom: 2.0, at: t0 + 30)
        #expect(machine.phase == .ready)
        #expect(machine.failures == 0)
    }

    @Test func `timeout and cooldown boundaries`() {
        var machine = EngagementMachine(configuration: config)
        machine.start(at: t0)
        machine.observe(headroom: 1.0, at: t0 + 25)   // exactly the timeout: still waiting
        #expect(machine.phase == .engaging(since: t0))
        machine.observe(headroom: 1.0, at: t0 + 25.5)
        #expect(machine.phase == .cooldown(until: t0 + 55.5))
        machine.observe(headroom: 1.0, at: t0 + 55.5)   // cooldown over at exactly `until`
        #expect(machine.phase == .engaging(since: t0 + 55.5))
    }

    @Test func `start after isolation retries from scratch`() {
        var machine = EngagementMachine(configuration: config)
        var now = t0
        machine.start(at: now)
        for _ in 0..<3 {
            now += 26
            machine.observe(headroom: 1.0, at: now)
            now += 31
            machine.observe(headroom: 1.0, at: now)
        }
        #expect(machine.phase == .isolated)
        machine.start(at: now)
        #expect(machine.phase == .engaging(since: now))
        #expect(machine.failures == 0)
    }
}
