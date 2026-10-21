import Foundation
import IOKit.pwr_mgt
import IlluminateCore
import os

/// Polls display-sleep power assertions to guess whether video is playing.
///
/// macOS has no public per-process HDR signal, and the EDR headroom is already
/// saturated by our own overlay, so this is an approximation by design.
final class PlaybackMonitor {
    private static let interval: Duration = .seconds(2)

    var onChange: (Bool) -> Void = { _ in }
    private(set) var isPlaybackLikely = false
    private let policy = PlaybackPolicy()
    private var state = PlaybackState()
    private var task: Task<Void, Never>?

    func start() {
        guard task == nil else { return }
        task = Task { [weak self] in
            // Ends with the monitor instead of polling a nil reference forever.
            while !Task.isCancelled, self != nil {
                self?.poll()
                try? await Task.sleep(for: Self.interval)
            }
        }
    }

    func stop() {
        task?.cancel()
        task = nil
        state = PlaybackState()
        update(false)
    }

    private func poll() {
        let likely = Self.currentAssertions().map { policy.isPlaybackLikely($0) }
        state.observe(likely, at: .now)
        update(state.isPlaybackLikely)
    }

    private func update(_ value: Bool) {
        guard value != isPlaybackLikely else { return }
        isPlaybackLikely = value
        Log.events.info("Playback likely: \(value)")
        onChange(value)
    }

    private static func currentAssertions() -> [DisplayAssertion]? {
        var unmanaged: Unmanaged<CFDictionary>?
        guard IOPMCopyAssertionsByProcess(&unmanaged) == kIOReturnSuccess,
              let byProcess = unmanaged?.takeRetainedValue() as? [NSNumber: [[String: Any]]]
        else { return nil }
        return byProcess.values.flatMap { assertions in
            assertions.compactMap { assertion in
                guard let type = assertion[kIOPMAssertionTypeKey as String] as? String,
                      let name = assertion["Process Name"] as? String,
                      let level = assertion[kIOPMAssertionLevelKey as String] as? NSNumber else { return nil }
                return DisplayAssertion(processName: name, type: type, isActive: level.uint32Value == kIOPMAssertionLevelOn)
            }
        }
    }
}
