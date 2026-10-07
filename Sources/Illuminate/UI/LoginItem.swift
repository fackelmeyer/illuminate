import Foundation
import IlluminateCore
import ServiceManagement

/// Launch at login via `SMAppService.mainApp`. The state always comes from the
/// system, never from a stored flag, because the user can change it in System Settings.
enum LoginItem {
    static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    static var needsApproval: Bool {
        SMAppService.mainApp.status == .requiresApproval
    }

    static var location: InstallLocation {
        InstallLocation(
            bundlePath: Bundle.main.bundlePath,
            homeDirectory: FileManager.default.homeDirectoryForCurrentUser.path
        )
    }

    static func setEnabled(_ enabled: Bool) {
        do {
            if enabled {
                guard location.canRegisterLoginItem else {
                    Log.app.notice("Not registering login item from \(Bundle.main.bundlePath, privacy: .public)")
                    return
                }
                try SMAppService.mainApp.register()
                if needsApproval { SMAppService.openSystemSettingsLoginItems() }
            } else {
                try SMAppService.mainApp.unregister()
            }
            Log.app.info("Login item \(enabled ? "registered" : "unregistered", privacy: .public): status \(SMAppService.mainApp.status.rawValue)")
        } catch {
            Log.app.error("Login item change failed: \(error.localizedDescription, privacy: .public)")
            // Let the user fix it by hand rather than failing silently.
            SMAppService.openSystemSettingsLoginItems()
        }
    }
}
