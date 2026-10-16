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
    private var task: Task<Void, Never>?

    func start() {
        guard task == nil else { return }
        task = Task { [weak self] in
            while !Task.isCancelled {
                self?.poll()
                try? await Task.sleep(for: Self.interval)
            }
        }
    }

    func stop() {
        task?.cancel()
        task = nil
        update(false)
    }

    private func poll() {
        update(policy.isPlaybackLikely(Self.currentAssertions()))
    }

    private func update(_ value: Bool) {
        guard value != isPlaybackLikely else { return }
        isPlaybackLikely = value
        Log.events.info("Playback likely: \(value)")
        onChange(value)
    }

    private static func currentAssertions() -> [DisplayAssertion] {
        var unmanaged: Unmanaged<CFDictionary>?
        guard IOPMCopyAssertionsByProcess(&unmanaged) == kIOReturnSuccess,
              let byProcess = unmanaged?.takeRetainedValue() as? [NSNumber: [[String: Any]]]
        else { return [] }
        return byProcess.values.flatMap { assertions in
            assertions.compactMap { assertion in
                guard let type = assertion["AssertType"] as? String,
                      let name = assertion["Process Name"] as? String else { return nil }
                return DisplayAssertion(processName: name, type: type)
            }
        }
    }
}
