import Testing
@testable import IlluminateCore

@Suite struct SuspensionStateTests {
    @Test func `starts unsuspended`() {
        let state = SuspensionState()
        #expect(state.isSuspended == false)
        #expect(state.reasons.isEmpty)
    }

    @Test func `first reason suspends`() {
        var state = SuspensionState()
        #expect(state.insert(.screenLocked) == .suspended)
        #expect(state.isSuspended)
    }

    @Test func `second reason does not transition again`() {
        var state = SuspensionState()
        state.insert(.screenLocked)
        #expect(state.insert(.screenSaver) == .unchanged)
    }

    @Test func `resumes only after every reason is cleared`() {
        // The bug this guards against: resuming on `screenSaver.didStop`
        // while the lock screen is still up.
        var state = SuspensionState()
        state.insert(.screenSaver)
        state.insert(.screenLocked)
        #expect(state.remove(.screenSaver) == .unchanged)
        #expect(state.isSuspended)
        #expect(state.remove(.screenLocked) == .resumed)
        #expect(state.isSuspended == false)
    }

    @Test func `removing an absent reason is a no-op`() {
        var state = SuspensionState()
        #expect(state.remove(.systemSleep) == .unchanged)
    }

    @Test func `inserting a present reason is a no-op`() {
        var state = SuspensionState()
        state.insert(.lowBattery)
        #expect(state.insert(.lowBattery) == .unchanged)
    }

    @Test func `primary reason follows declaration order`() {
        // A Set has no order; the menu must not flip between reasons.
        var state = SuspensionState()
        #expect(state.primaryReason == nil)
        state.insert(.displaysAsleep)
        state.insert(.lowBattery)
        state.insert(.screenLocked)
        #expect(state.primaryReason == .screenLocked)
    }

    @Test func `set(_:active:) inserts and removes`() {
        var state = SuspensionState()
        #expect(state.set(.lowPowerMode, active: true) == .suspended)
        #expect(state.set(.lowPowerMode, active: true) == .unchanged)
        #expect(state.set(.lowPowerMode, active: false) == .resumed)
    }
}
