import ServiceManagement

/// Thin wrapper over `SMAppService.mainApp` for the Settings toggle.
enum LoginItemManager {
    static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    static func setEnabled(_ enabled: Bool) {
        do {
            if enabled {
                if SMAppService.mainApp.status != .enabled {
                    try SMAppService.mainApp.register()
                }
            } else {
                if SMAppService.mainApp.status == .enabled {
                    try SMAppService.mainApp.unregister()
                }
            }
        } catch {
            // Best-effort: SMAppService can fail if the app isn't installed in /Applications yet
            // (common during local `xcodebuild` development). Not fatal — just leave the setting
            // as the user asked and let them retry once the app is properly installed.
        }
    }
}
