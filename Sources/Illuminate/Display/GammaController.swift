import CoreGraphics
import Foundation
import IlluminateCore
import os

/// Owns one display's transfer table: captures the baseline, writes scaled
/// versions, detects drift, and restores.
final class GammaController {
    enum Health {
        case ok
        /// macOS reset the table (wake, True Tone, reconfiguration).
        case drifted
        /// The all-black table `CGDisplayRestoreColorSyncSettings` sometimes leaves behind.
        case degenerate
    }

    let display: CGDirectDisplayID
    private var baseline: GammaTable?
    private var applied: GammaTable?

    init(display: CGDirectDisplayID) {
        self.display = display
    }

    /// Reads the current table as the baseline to scale. Call before the first `apply`.
    @discardableResult
    func captureBaseline() -> Bool {
        guard let table = read() else { return false }
        // Never adopt a broken table as the reference; fall back to a linear ramp.
        baseline = table.isDegenerate ? .identity(count: table.count) : table
        return true
    }

    func apply(gain: Double) {
        if baseline == nil, !captureBaseline() { return }
        guard let baseline else { return }
        let table = gain <= 1.0001 ? baseline : baseline.scaled(by: Float(gain))
        if write(table) {
            applied = table
            if table != baseline { GammaSafety.markDirty() }
        }
    }

    func health() -> Health {
        guard let applied, let current = read() else { return .ok }
        if current.isDegenerate { return .degenerate }
        // Readback clamps at 1 even while the boosted values are in effect.
        return current.isApproximatelyEqual(to: applied.clamped(to: 1), tolerance: 0.01) ? .ok : .drifted
    }

    /// Writes the captured baseline back. Leaves other displays and apps untouched,
    /// unlike `CGDisplayRestoreColorSyncSettings`.
    func restore() {
        guard let baseline else { return }
        write(baseline)
        applied = nil
    }

    private func read() -> GammaTable? {
        let capacity = Int(CGDisplayGammaTableCapacity(display))
        guard capacity >= 2 else { return nil }
        var red = [CGGammaValue](repeating: 0, count: capacity)
        var green = red
        var blue = red
        var count: UInt32 = 0
        let error = CGGetDisplayTransferByTable(display, UInt32(capacity), &red, &green, &blue, &count)
        guard error == .success, count >= 2 else {
            Log.gamma.error("Reading gamma of display \(self.display) failed: \(error.rawValue)")
            return nil
        }
        let used = Int(count)
        return GammaTable(red: Array(red[..<used]), green: Array(green[..<used]), blue: Array(blue[..<used]))
    }

    @discardableResult
    private func write(_ table: GammaTable) -> Bool {
        let error = CGSetDisplayTransferByTable(display, UInt32(table.count), table.red, table.green, table.blue)
        if error != .success {
            Log.gamma.error("Writing gamma of display \(self.display) failed: \(error.rawValue)")
        }
        return error == .success
    }
}

/// Makes sure a boosted gamma table never outlives the process.
///
/// A gamma table is persistent system state: if we die with a scaled table, the
/// screen stays washed out. Layers of defence:
/// 1. `atexit` and SIGTERM/SIGINT/SIGHUP/SIGQUIT handlers restore on any orderly exit.
/// 2. A "dirty" marker in UserDefaults survives crashes; the next launch restores.
enum GammaSafety {
    fileprivate nonisolated static let dirtyKey = "gamma.dirty"
    private static var signalSources: [any DispatchSourceSignal] = []

    /// Call first thing at launch.
    static func recoverIfNeeded() {
        guard UserDefaults.standard.bool(forKey: dirtyKey) else { return }
        Log.gamma.notice("Previous session left a boosted gamma table; restoring ColorSync settings")
        CGDisplayRestoreColorSyncSettings()
        UserDefaults.standard.set(false, forKey: dirtyKey)
    }

    static func markDirty() {
        guard !UserDefaults.standard.bool(forKey: dirtyKey) else { return }
        UserDefaults.standard.set(true, forKey: dirtyKey)
        installExitHandlers()
    }

    /// Every boosted table has been written back to its baseline.
    static func markClean() {
        UserDefaults.standard.set(false, forKey: dirtyKey)
    }

    static func restoreAll() {
        guard UserDefaults.standard.bool(forKey: dirtyKey) else { return }
        CGDisplayRestoreColorSyncSettings()
        UserDefaults.standard.set(false, forKey: dirtyKey)
    }

    private static func installExitHandlers() {
        guard signalSources.isEmpty else { return }
        atexit(restoreGammaAtExit)
        for number in [SIGTERM, SIGINT, SIGHUP, SIGQUIT] {
            // Ignore the default action so the dispatch source receives the signal instead.
            signal(number, SIG_IGN)
            let source = DispatchSource.makeSignalSource(signal: number, queue: .main)
            source.setEventHandler {
                MainActor.assumeIsolated { restoreAll() }
                exit(0)
            }
            source.resume()
            signalSources.append(source)
        }
    }
}

/// Runs on whichever thread called `exit()`; both calls are thread-safe.
private nonisolated func restoreGammaAtExit() {
    if UserDefaults.standard.bool(forKey: GammaSafety.dirtyKey) {
        CGDisplayRestoreColorSyncSettings()
    }
}
