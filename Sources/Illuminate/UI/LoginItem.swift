import Foundation
import IlluminateCore
import ServiceManagement
import os

/// Launch at login via `SMAppService.mainApp`. The state always comes from the
/// system, never from a stored flag, because the user can change it in System Settings.
enum LoginItem {
    enum State {
        case enabled
        case requiresApproval
        case disabled
    }

    /// Each read is a synchronous round-trip to the system, so read it once per use.
    static var state: State {
        switch SMAppService.mainApp.status {
        case .enabled: .enabled
        case .requiresApproval: .requiresApproval
        default: .disabled
        }
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
                if state == .requiresApproval { SMAppService.openSystemSettingsLoginItems() }
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
