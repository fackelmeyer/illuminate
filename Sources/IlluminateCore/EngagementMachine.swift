/// Tracks whether a display has granted EDR headroom after we asked for it.
///
/// One instance per display, so a stubborn external monitor can never
/// switch off the boost on the built-in panel. Time is injected, which keeps
/// the machine deterministic under test; it is monotonic, so a clock change
/// cannot stretch or skip a timeout.
public struct EngagementMachine: Sendable {
    public typealias Instant = ContinuousClock.Instant

    public struct Configuration: Equatable, Sendable {
        /// Headroom above which EDR counts as engaged.
        public var readyThreshold: Double
        /// How long to wait for headroom before giving up for a while.
        public var timeout: Duration
        /// Pause between attempts.
        public var cooldown: Duration
        /// Failed attempts before the display stops retrying (it still recovers if headroom appears).
        public var maximumFailures: Int

        public init(readyThreshold: Double = 1.05, timeout: Duration = .seconds(25), cooldown: Duration = .seconds(30), maximumFailures: Int = 3) {
            self.readyThreshold = readyThreshold
            self.timeout = timeout
            self.cooldown = cooldown
            self.maximumFailures = maximumFailures
        }
    }

    public enum Phase: Equatable, Sendable {
        case idle
        case engaging(since: Instant)
        case ready
        case cooldown(until: Instant)
        case isolated
    }

    public let configuration: Configuration
    public private(set) var phase: Phase = .idle
    public private(set) var failures = 0

    public init(configuration: Configuration = .init()) {
        self.configuration = configuration
    }

    public mutating func start(at now: Instant) {
        failures = 0
        phase = .engaging(since: now)
    }

    public mutating func stop() {
        failures = 0
        phase = .idle
    }

    /// Feeds one headroom sample. Call it on a timer and after display changes.
    public mutating func observe(headroom: Double, at now: Instant) {
        let engaged = headroom > configuration.readyThreshold
        switch phase {
        case .idle:
            return
        case .isolated:
            // Stop actively retrying, but take headroom if the system grants it after all.
            if engaged {
                failures = 0
                phase = .ready
            }
        case .engaging(let since):
            if engaged {
                failures = 0
                phase = .ready
            } else if since.duration(to: now) > configuration.timeout {
                failures += 1
                phase = .cooldown(until: now + configuration.cooldown)
            }
        case .ready:
            if !engaged {
                phase = .engaging(since: now)
            }
        case .cooldown(let until):
            if engaged {
                failures = 0
                phase = .ready
            } else if now >= until {
                phase = failures >= configuration.maximumFailures ? .isolated : .engaging(since: now)
            }
        }
    }
}
