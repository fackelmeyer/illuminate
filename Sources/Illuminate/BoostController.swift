import AppKit
import IlluminateCore
import os

/// The app's single source of truth: preferences, suspension reasons and
/// one `DisplayBooster` per eligible display.
final class BoostController {
    /// Poll rates. Headroom is not KVO-observable, so it is sampled.
    private static let restInterval: Duration = .milliseconds(500)
    private static let burstInterval: Duration = .milliseconds(50)
    /// Sample fast for this long after any change, to apply the gain as soon as headroom arrives.
    private static let burstDuration: TimeInterval = 10
    /// Step for the increase/decrease hotkeys.
    static let levelStep = 0.1

    private(set) var preferences: Preferences
    private(set) var suspension = SuspensionState()
    private(set) var isPlaybackLikely = false
    let gammaCompatibility: GammaCompatibility

    var onStatusChange: () -> Void = {}

    private let store: PreferencesStore
    private let curve = BoostCurve()
    private var boosters: [CGDirectDisplayID: DisplayBooster] = [:]
    private var tickTask: Task<Void, Never>?
    private var burstUntil = Date.distantPast
    private var lastStatuses: [DisplayStatus] = []
    private var power: PowerStatus?

    init(store: PreferencesStore = PreferencesStore(), cpuBrand: String) {
        self.store = store
        preferences = store.load()
        gammaCompatibility = GammaCompatibility(cpuBrand: cpuBrand)
    }

    // MARK: Inputs

    func start() {
        rebuildDisplays()
        applyState()
    }

    func update(_ change: (inout Preferences) -> Void) {
        let old = preferences
        change(&preferences)
        guard preferences != old else { return }
        store.save(preferences)
        if preferences.technique != old.technique { rebuildDisplays(force: true) }
        // Battery and Low Power Mode rules may have changed.
        refreshPowerReasons()
        applyState()
    }

    func adjustLevel(by delta: Double) {
        update {
            $0.isEnabled = true
            $0.level += delta
        }
    }

    func setSuspended(_ reason: SuspensionReason, _ active: Bool) {
        let transition = suspension.set(reason, active: active)
        guard transition != .unchanged else { return }
        Log.events.info("Suspension \(reason.rawValue, privacy: .public)=\(active) -> \(String(describing: self.suspension.reasons), privacy: .public)")
        applyState()
    }

    func setPower(_ power: PowerStatus) {
        self.power = power
        if refreshPowerReasons() { applyState() }
    }

    func setPlaybackLikely(_ value: Bool) {
        isPlaybackLikely = value
        burst()
    }

    func displaysChanged() {
        rebuildDisplays()
        applyState()
        burst()
    }

    func shutdown() {
        tickTask?.cancel()
        tickTask = nil
        for booster in boosters.values { booster.tearDown() }
        boosters.removeAll()
        GammaSafety.markClean()
    }

    // MARK: Outputs

    /// The technique actually in use. Gamma is unusable on M5 Pro/Max.
    var effectiveTechnique: BoostTechniqueKind {
        preferences.technique == .gamma && gammaCompatibility.isGammaBroken ? .overlay : preferences.technique
    }

    var hasEligibleDisplay: Bool { !boosters.isEmpty }

    var isBoosting: Bool {
        preferences.isEnabled && !suspension.isSuspended && hasEligibleDisplay
    }

    var statuses: [DisplayStatus] {
        boosters.values
            .sorted { $0.profile.isBuiltin && !$1.profile.isBuiltin }
            .map(\.status)
    }

    // MARK: Internals

    private var effectiveLevel: Double {
        isPlaybackLikely && preferences.reduceDuringPlayback ? 0 : preferences.level
    }

    /// Re-derives the battery and Low Power Mode reasons. Returns whether suspension changed.
    @discardableResult
    private func refreshPowerReasons() -> Bool {
        guard let power else { return false }
        let reasons = power.suspensionReasons(for: preferences)
        let before = suspension
        for reason in [SuspensionReason.lowBattery, .lowPowerMode] {
            suspension.set(reason, active: reasons.contains(reason))
        }
        guard suspension != before else { return false }
        Log.events.info("Power \(String(describing: power), privacy: .public) -> suspension \(String(describing: self.suspension.reasons), privacy: .public)")
        return true
    }

    private func rebuildDisplays(force: Bool = false) {
        let kind = effectiveTechnique
        var current: [CGDirectDisplayID: NSScreen] = [:]
        for screen in NSScreen.screens {
            guard let id = screen.displayID, let profile = screen.profile, profile.isEligible else { continue }
            current[id] = screen
        }

        for (id, booster) in boosters where force || current[id] == nil || booster.kind != kind {
            booster.tearDown()
            boosters[id] = nil
        }
        if boosters.isEmpty { GammaSafety.markClean() }

        for (id, screen) in current where boosters[id] == nil {
            guard let profile = screen.profile,
                  let booster = DisplayBooster(display: id, screen: screen, profile: profile, kind: kind)
            else { continue }
            Log.display.info("Boosting \(profile.name, privacy: .public) (potential headroom \(profile.potentialHeadroom)) with \(kind.rawValue, privacy: .public)")
            boosters[id] = booster
        }
    }

    private func applyState() {
        let active = isBoosting
        for booster in boosters.values { booster.setActive(active) }
        if active {
            burst()
            startTicking()
        } else {
            stopTicking()
            GammaSafety.markClean()
        }
        publishStatus(force: true)
    }

    private func burst() {
        burstUntil = Date.now + Self.burstDuration
    }

    private func startTicking() {
        guard tickTask == nil else { return }
        tickTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let interval = self?.tick() else { return }
                try? await Task.sleep(for: interval)
            }
        }
    }

    private func stopTicking() {
        tickTask?.cancel()
        tickTask = nil
    }

    /// Samples every display once. Returns the delay until the next sample.
    private func tick() -> Duration {
        let now = Date.now
        let screens = Dictionary(NSScreen.screens.compactMap { s in s.displayID.map { ($0, s) } }, uniquingKeysWith: { a, _ in a })
        for (id, booster) in boosters {
            guard let screen = screens[id] else { continue }
            booster.tick(screen: screen, level: effectiveLevel, curve: curve, now: now)
        }
        publishStatus()
        return now < burstUntil ? Self.burstInterval : Self.restInterval
    }

    private func publishStatus(force: Bool = false) {
        // Round so the menu is not redrawn for sub-nit jitter.
        let statuses = self.statuses.map { status in
            var status = status
            status.gain = (status.gain * 100).rounded() / 100
            status.nits = status.nits.map { ($0 / 10).rounded() * 10 }
            return status
        }
        guard force || statuses != lastStatuses else { return }
        lastStatuses = statuses
        onStatusChange()
    }
}
