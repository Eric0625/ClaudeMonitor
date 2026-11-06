import AppKit
import ClaudeMonitorCore

/// Opens a session in the Claude app.
@MainActor
enum SessionOpener {
    static func open(_ target: SessionOpenTarget) {
        guard let claudeURL = NSWorkspace.shared.urlForApplication(
            withBundleIdentifier: SessionOpenTarget.claudeBundleIdentifier
        ) else {
            NSSound.beep()
            return
        }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true

        switch target {
        case .deepLink(let url):
            NSWorkspace.shared.open([url], withApplicationAt: claudeURL, configuration: configuration) { _, error in
                guard error != nil else { return }
                // Fallback when Claude turns off its deep links.
                Task { @MainActor in
                    activate(claudeURL)
                }
            }
        case .activateClaude:
            activate(claudeURL)
        }
    }

    private static func activate(_ claudeURL: URL) {
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        NSWorkspace.shared.openApplication(at: claudeURL, configuration: configuration)
    }
}
