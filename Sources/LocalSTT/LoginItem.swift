import Foundation
import ServiceManagement

/// Handles login-item registration through `SMAppService`.
///
/// Registration is bound to the bundle's location, so relocating the app
/// invalidates it — the preferences UI warns about this and recommends
/// `/Applications`.
@MainActor
enum LoginItem {

    static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    /// True once macOS knows about the request while the user still hasn't
    /// confirmed it under System Settings ▸ General ▸ Login Items.
    static var needsApproval: Bool {
        SMAppService.mainApp.status == .requiresApproval
    }

    static func setEnabled(_ enabled: Bool) throws {
        if enabled {
            try SMAppService.mainApp.register()
        } else {
            try SMAppService.mainApp.unregister()
        }
    }

    static func openLoginItemsSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }
}
