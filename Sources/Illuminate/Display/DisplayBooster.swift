import AppKit
import IlluminateCore
import os

/// What the menu shows for one display.
struct DisplayStatus: Equatable {
    enum State: Equatable {
        case off
        case engaging
        case boosting
        case unavailable
    }

    var name: String
    var state: State
    var gain: Double
    var nits: Double?
}

/// Drives one display: asks for EDR headroom, waits until it is granted,
/// then keeps the technique's gain inside what the headroom allows.
final class DisplayBooster {
    let display: CGDirectDisplayID
    let profile: DisplayProfile
    let kind: BoostTechniqueKind
    private let technique: any BoostTechnique
    private var machine = EngagementMachine()
    private var isActive = false
    private(set) var headroom = 1.0
    private(set) var gain = 1.0

    init?(display: CGDirectDisplayID, screen: NSScreen, profile: DisplayProfile, kind: BoostTechniqueKind) {
        let technique: (any BoostTechnique)? = switch kind {
        case .overlay: OverlayTechnique(screen: screen)
        case .gamma: GammaTechnique(screen: screen, display: display)
        }
        guard let technique else { return nil }
        self.display = display
        self.profile = profile
        self.kind = kind
        self.technique = technique
    }

    func setActive(_ active: Bool, now: ContinuousClock.Instant = .now) {
        guard active != isActive else { return }
        isActive = active
        if active {
            technique.activate()
            machine.start(at: now)
        } else {
            technique.deactivate()
            machine.stop()
            gain = 1
        }
    }

    /// - Parameter level: boost level in `0...1`; 0 keeps EDR engaged but adds no gain.
    func tick(screen: NSScreen, level: Double, curve: BoostCurve, now: ContinuousClock.Instant = .now) {
        guard isActive else { return }
        technique.maintain(screen: screen)
        headroom = Double(screen.maximumExtendedDynamicRangeColorComponentValue)

        let previous = machine.phase
        machine.observe(headroom: headroom, at: now)
        if case .cooldown = previous, case .engaging = machine.phase {
            // Retry from scratch: release and re-request EDR.
            Log.display.notice("Retrying EDR on \(self.profile.name, privacy: .public)")
            technique.deactivate()
            technique.activate()
        }
        if previous != machine.phase {
            Log.display.info("\(self.profile.name, privacy: .public): \(String(describing: self.machine.phase), privacy: .public), headroom \(self.headroom)")
        }

        // Without headroom, any gain above 1 clips to a flat, washed-out image.
        let target = machine.phase == .ready
            ? curve.targetGain(level: level, headroom: headroom, panelPeakNits: profile.panelPeakNits)
            : 1
        if abs(target - gain) > 0.001 {
            gain = target
            technique.apply(gain: gain)
        }
    }

    func tearDown() {
        setActive(false)
        technique.tearDown()
    }

    var status: DisplayStatus {
        let state: DisplayStatus.State = switch machine.phase {
        case .idle: .off
        case .engaging, .cooldown: .engaging
        case .ready: .boosting
        case .isolated: .unavailable
        }
        let nits = profile.panelPeakNits
            .flatMap { NitsEstimate(panelPeakNits: $0, headroom: headroom) }
            .map { $0.boostedNits(gain: gain) }
        return DisplayStatus(name: profile.name, state: state, gain: gain, nits: state == .boosting ? nits : nil)
    }
}

extension NSScreen {
    var displayID: CGDirectDisplayID? {
        (deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value
    }

    var profile: DisplayProfile? {
        guard let displayID else { return nil }
        return DisplayProfile(
            name: localizedName,
            isBuiltin: CGDisplayIsBuiltin(displayID) != 0,
            potentialHeadroom: Double(maximumPotentialExtendedDynamicRangeColorComponentValue)
        )
    }
}
