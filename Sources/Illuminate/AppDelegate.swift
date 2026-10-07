import AppKit
import IlluminateCore

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var controller: BoostController?
    private var menu: StatusMenuController?
    private let events = SystemEventMonitor()
    private let power = PowerMonitor()
    private let playback = PlaybackMonitor()
    private let hotKeys = HotKeys()

    func applicationDidFinishLaunching(_ notification: Notification) {
        guard !Self.isAnotherInstanceRunning else {
            Log.app.notice("Another instance is running; exiting")
            NSApp.terminate(nil)
            return
        }
        // Undo a boosted gamma table a crashed session may have left behind,
        // before anything captures it as a baseline.
        GammaSafety.recoverIfNeeded()

        let controller = BoostController(cpuBrand: Self.cpuBrand)
        self.controller = controller
        let menu = StatusMenuController(controller: controller)
        self.menu = menu
        controller.onStatusChange = { [weak menu] in menu?.refresh() }

        events.onSuspensionChange = { [weak controller] reason, active in controller?.setSuspended(reason, active) }
        events.onDisplaysChanged = { [weak controller] in controller?.displaysChanged() }
        events.start()

        power.onChange = { [weak controller] status in controller?.setPower(status) }
        power.start()

        playback.onChange = { [weak controller] likely in controller?.setPlaybackLikely(likely) }
        playback.start()

        hotKeys.onAction = { [weak controller] action in
            guard let controller else { return }
            switch action {
            case .toggle: controller.update { $0.isEnabled.toggle() }
            case .increase: controller.adjustLevel(by: BoostController.levelStep)
            case .decrease: controller.adjustLevel(by: -BoostController.levelStep)
            }
        }
        hotKeys.register()

        controller.start()
        Log.app.info("Illuminate started on \(Self.cpuBrand, privacy: .public)")
    }

    func applicationWillTerminate(_ notification: Notification) {
        hotKeys.unregister()
        playback.stop()
        power.stop()
        events.stop()
        controller?.shutdown()
    }

    private static var isAnotherInstanceRunning: Bool {
        guard let bundleID = Bundle.main.bundleIdentifier else { return false }
        let pid = ProcessInfo.processInfo.processIdentifier
        return NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
            .contains { $0.processIdentifier != pid }
    }

    private static var cpuBrand: String {
        var size = 0
        guard sysctlbyname("machdep.cpu.brand_string", nil, &size, nil, 0) == 0, size > 0 else { return "" }
        var buffer = [CChar](repeating: 0, count: size)
        guard sysctlbyname("machdep.cpu.brand_string", &buffer, &size, nil, 0) == 0 else { return "" }
        return String(decoding: buffer.prefix { $0 != 0 }.map(UInt8.init), as: UTF8.self)
    }
}
