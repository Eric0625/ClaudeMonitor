import Foundation
import Observation
import os
import ServiceManagement

/// The "Launch at Login" setting, stored by `SMAppService.mainApp`.
@MainActor
@Observable
final class LaunchAtLogin {
    private(set) var isEnabled = SMAppService.mainApp.status == .enabled

    @ObservationIgnored private let logger = Logger(subsystem: "com.ericyuan.ClaudeMonitor", category: "launch-at-login")

    func setEnabled(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            logger.error("Launch at Login change failed: \(error.localizedDescription, privacy: .public)")
        }
        if SMAppService.mainApp.status == .requiresApproval {
            SMAppService.openSystemSettingsLoginItems()
        }
        refresh()
    }

    func refresh() {
        isEnabled = SMAppService.mainApp.status == .enabled
    }
}
