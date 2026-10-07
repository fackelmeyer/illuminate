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

    public init(processName: String, type: String) {
        self.processName = processName
        self.type = type
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
        assertions.contains { assertionTypes.contains($0.type) && !ignoredProcesses.contains($0.processName) }
    }
}
