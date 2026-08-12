import Foundation
import ServiceManagement

final class LoginItemManager {
    var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    var needsApprovalInSystemSettings: Bool {
        SMAppService.mainApp.status == .requiresApproval
    }

    @discardableResult
    func setEnabled(_ enabled: Bool) -> Bool {
        do {
            if enabled {
                guard SMAppService.mainApp.status != .enabled else { return true }
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            return true
        } catch {
            return false
        }
    }

    func openSystemSettingsIfNeeded() {
        guard needsApprovalInSystemSettings else { return }
        SMAppService.openSystemSettingsLoginItems()
    }
}
