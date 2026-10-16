import AppKit
import CoreGraphics
import IlluminateCore
import os

/// Turns the system notifications that affect EDR into two signals:
/// suspension changes and "displays need re-applying".
///
/// WindowServer withdraws EDR headroom ~15 s after our surface is hidden
/// (screen saver, lock screen, display sleep). Suspending explicitly on
/// those events avoids a flat, clipped image when headroom disappears
/// under a still-applied boost.
final class SystemEventMonitor {
    var onSuspensionChange: (SuspensionReason, Bool) -> Void = { _, _ in }
    /// Display set, arrangement or colour state may have changed; rebuild and re-apply.
    var onDisplaysChanged: () -> Void = {}

    private var observations: [(NotificationCenter, any NSObjectProtocol)] = []
    private var debounce: DispatchWorkItem?

    func start() {
        let workspace = NSWorkspace.shared.notificationCenter
        let distributed = DistributedNotificationCenter.default()

        observe(distributed, "com.apple.screensaver.didstart") { $0.onSuspensionChange(.screenSaver, true) }
        observe(distributed, "com.apple.screensaver.didstop") { $0.onSuspensionChange(.screenSaver, false) }
        observe(distributed, "com.apple.screenIsLocked") { $0.onSuspensionChange(.screenLocked, true) }
        observe(distributed, "com.apple.screenIsUnlocked") { $0.onSuspensionChange(.screenLocked, false) }

        observe(workspace, NSWorkspace.sessionDidResignActiveNotification.rawValue) { $0.onSuspensionChange(.sessionInactive, true) }
        observe(workspace, NSWorkspace.sessionDidBecomeActiveNotification.rawValue) { $0.onSuspensionChange(.sessionInactive, false) }
        observe(workspace, NSWorkspace.willSleepNotification.rawValue) { $0.onSuspensionChange(.systemSleep, true) }
        observe(workspace, NSWorkspace.didWakeNotification.rawValue) { $0.onSuspensionChange(.systemSleep, false) }
        // A display-only wake after locking sends screensDidWake but no didWake.
        observe(workspace, NSWorkspace.screensDidSleepNotification.rawValue) { $0.onSuspensionChange(.displaysAsleep, true) }
        observe(workspace, NSWorkspace.screensDidWakeNotification.rawValue) { monitor in
            monitor.onSuspensionChange(.displaysAsleep, false)
            monitor.scheduleDisplaysChanged()
        }

        observe(.default, NSApplication.didChangeScreenParametersNotification.rawValue) { $0.scheduleDisplaysChanged() }

        CGDisplayRegisterReconfigurationCallback(displayReconfigured, Unmanaged.passUnretained(self).toOpaque())
    }

    func stop() {
        for (center, token) in observations { center.removeObserver(token) }
        observations.removeAll()
        CGDisplayRemoveReconfigurationCallback(displayReconfigured, Unmanaged.passUnretained(self).toOpaque())
    }

    /// Coalesces bursts (hot-plug and wake send several events) into one rebuild.
    func scheduleDisplaysChanged() {
        debounce?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.onDisplaysChanged() }
        debounce = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: work)
    }

    private func observe(_ center: NotificationCenter, _ name: String, _ handler: @escaping @MainActor (SystemEventMonitor) -> Void) {
        let token = center.addObserver(forName: Notification.Name(name), object: nil, queue: .main) { [weak self] notification in
            Log.events.debug("\(notification.name.rawValue, privacy: .public)")
            MainActor.assumeIsolated {
                guard let self else { return }
                handler(self)
            }
        }
        observations.append((center, token))
    }
}

/// CoreGraphics calls this on the main run loop for each display, before and after a change.
private nonisolated func displayReconfigured(_ display: CGDirectDisplayID, _ flags: CGDisplayChangeSummaryFlags, _ context: UnsafeMutableRawPointer?) {
    guard let context, !flags.contains(.beginConfigurationFlag) else { return }
    let monitor = Unmanaged<SystemEventMonitor>.fromOpaque(context).takeUnretainedValue()
    MainActor.assumeIsolated { monitor.scheduleDisplaysChanged() }
}
