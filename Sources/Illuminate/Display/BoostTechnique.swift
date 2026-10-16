import AppKit
import IlluminateCore
import os

/// One way of turning EDR headroom into brighter SDR content on one display.
///
/// Lifecycle: `activate()` requests headroom; `apply(gain:)` is called on every
/// tick once headroom is granted (and with 1 while it is not); `deactivate()`
/// removes every visible effect but keeps resources for the next activation.
protocol BoostTechnique: AnyObject {
    func activate()
    func apply(gain: Double)
    func deactivate()
    /// Called on every tick with the current screen, for re-anchoring and drift repair.
    func maintain(screen: NSScreen)
    /// Final cleanup before the display goes away or the app quits.
    func tearDown()
}

/// Default technique: a full-screen EDR window with a multiply compositing filter.
///
/// Leaves HDR video intact (it is multiplied rather than clipped) and leaves no
/// system state behind: if the process dies, WindowServer removes the window.
final class OverlayTechnique: BoostTechnique {
    private let window: EDRWindow

    init?(screen: NSScreen) {
        guard let window = EDRWindow(role: .overlay, screen: screen) else { return nil }
        self.window = window
    }

    func activate() {
        window.setGain(1)
        window.setActive(true)
    }

    func apply(gain: Double) {
        window.setGain(gain)
    }

    func deactivate() {
        window.setGain(1)
        window.setActive(false)
    }

    func maintain(screen: NSScreen) {
        // An HDR mode switch can park the overlay on a neighbouring display.
        if window.frame != screen.frame { window.reposition(on: screen) }
    }

    func tearDown() {
        deactivate()
        window.close()
    }
}

/// Fallback: a 1×1 EDR trigger keeps headroom granted while the display's gamma
/// table is scaled above 1.
///
/// Colour-faithful, but clips HDR video, conflicts with other gamma apps (f.lux),
/// and leaves a persistent system state that `GammaSafety` must undo.
final class GammaTechnique: BoostTechnique {
    /// How often to compare the live table with what we wrote.
    private static let driftCheckInterval: Duration = .seconds(5)

    private let trigger: EDRWindow
    private let gamma: GammaController
    private var appliedGain = 1.0
    private var nextDriftCheck = ContinuousClock.now

    init?(screen: NSScreen, display: CGDirectDisplayID) {
        guard let trigger = EDRWindow(role: .trigger, screen: screen) else { return nil }
        self.trigger = trigger
        gamma = GammaController(display: display)
    }

    func activate() {
        // Capture before anything is scaled, so the baseline is the user's real profile.
        if appliedGain == 1 { gamma.captureBaseline() }
        trigger.setActive(true)
    }

    func apply(gain: Double) {
        // Only rewrite on a visible change; every write costs a WindowServer round-trip.
        guard abs(gain - appliedGain) > 0.002 else { return }
        gamma.apply(gain: gain)
        appliedGain = gain
    }

    func deactivate() {
        // Order matters: restore the table *before* EDR goes away, or the boosted
        // values clip to a flat, washed-out image for a moment.
        gamma.restore()
        appliedGain = 1
        trigger.setActive(false)
    }

    func maintain(screen: NSScreen) {
        trigger.reposition(on: screen)
        guard appliedGain > 1, ContinuousClock.now >= nextDriftCheck else { return }
        nextDriftCheck = .now + Self.driftCheckInterval
        switch gamma.health() {
        case .ok:
            break
        case .drifted:
            // The new table is the system's or another app's choice (a profile switch,
            // Night Shift); boost that instead of reverting to the old baseline.
            Log.gamma.notice("Gamma table of display \(self.gamma.display) was replaced; re-capturing and re-applying")
            gamma.captureBaseline()
            gamma.apply(gain: appliedGain)
        case .degenerate:
            Log.gamma.error("Gamma table of display \(self.gamma.display) is all black; re-capturing")
            gamma.captureBaseline()
            gamma.apply(gain: appliedGain)
        }
    }

    func tearDown() {
        deactivate()
        trigger.close()
    }
}
