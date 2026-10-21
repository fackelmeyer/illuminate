/// Known hardware where the gamma technique cannot work.
public struct GammaCompatibility: Equatable, Sendable {
    public let cpuBrand: String

    /// - Parameter cpuBrand: `sysctl machdep.cpu.brand_string`, e.g. "Apple M5 Max".
    public init(cpuBrand: String) {
        self.cpuBrand = cpuBrand
    }

    /// On M5 Pro and M5 Max, `CGSetDisplayTransferByTable` returns success and reads
    /// back correctly but has no visible effect (FB22273730, still open on macOS 27).
    /// Because readback succeeds, this cannot be detected at runtime.
    public var isGammaBroken: Bool {
        let words = cpuBrand.split(separator: " ")
        guard let chip = words.firstIndex(of: "M5"), words.index(after: chip) < words.endIndex else { return false }
        return ["Pro", "Max"].contains(words[words.index(after: chip)])
    }
}

/// One display-sleep power assertion, reduced to what the policy needs.
public struct DisplayAssertion: Equatable, Sendable {
    public var processName: String
    public var type: String
    public var isActive: Bool

    public init(processName: String, type: String, isActive: Bool = true) {
        self.processName = processName
        self.type = type
        self.isActive = isActive
    }
}

/// Heuristic for "video is playing": macOS has no public signal for HDR content on
/// screen, but players hold a display-sleep assertion while they play.
public struct PlaybackPolicy: Equatable, Sendable {
    public var assertionTypes: Set<String> = ["PreventUserIdleDisplaySleep", "NoDisplaySleepAssertion"]
    /// Processes that keep the display awake for reasons other than playback.
    public var ignoredProcesses: Set<String> = [
        "WindowServer", "powerd", "coreaudiod", "caffeinate", "Amphetamine",
        "loginwindow", "screensharingd", "Illuminate",
    ]

    public init() {}

    public func isPlaybackLikely(_ assertions: [DisplayAssertion]) -> Bool {
        assertions.contains { $0.isActive && assertionTypes.contains($0.type) && !ignoredProcesses.contains($0.processName) }
    }
}

/// Requires sustained evidence before changing playback state. The longer release
/// delay bridges assertion gaps while a browser or player moves to the background.
public struct PlaybackState: Sendable {
    public private(set) var isPlaybackLikely = false
    private var pendingSince: ContinuousClock.Instant?

    public init() {}

    /// A failed query is unknown, not evidence that playback stopped. It also breaks
    /// the pending confirmation period, so failures cannot count as stable samples.
    public mutating func observe(_ likely: Bool?, at now: ContinuousClock.Instant) {
        guard let likely, likely != isPlaybackLikely else {
            pendingSince = nil
            return
        }
        guard let pendingSince else {
            self.pendingSince = now
            return
        }
        let delay: Duration = likely ? .seconds(4) : .seconds(10)
        guard pendingSince.duration(to: now) >= delay else { return }
        isPlaybackLikely = likely
        self.pendingSince = nil
    }
}

/// Fades only the playback reduction, leaving the user's boost slider responsive.
public struct PlaybackDimming: Sendable {
    private var startFactor = 1.0
    private var targetFactor = 1.0
    private var startedAt: ContinuousClock.Instant?

    public init() {}

    public mutating func setReduced(_ reduced: Bool, at now: ContinuousClock.Instant) {
        let target = reduced ? 0.0 : 1.0
        guard target != targetFactor else { return }
        startFactor = factor(at: now)
        targetFactor = target
        startedAt = now
    }

    /// A one-second transition, continuous even if the reduction reverses midway.
    public func factor(at now: ContinuousClock.Instant) -> Double {
        guard let startedAt else { return targetFactor }
        let elapsed = startedAt.duration(to: now).components
        let seconds = Double(elapsed.seconds) + Double(elapsed.attoseconds) / 1e18
        let progress = min(max(seconds, 0), 1)
        let eased = progress * progress * (3 - 2 * progress)
        return startFactor + (targetFactor - startFactor) * eased
    }
}
