import AppKit
import ClaudeMonitorCore
import UserNotifications

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let notifications = UserNotificationPoster()
    private let launchAtLogin = LaunchAtLogin()
    private var monitor: SessionMonitor?
    private var driver: SessionRefreshDriver?
    private var statusItemController: StatusItemController?
    private var onboarding: OnboardingWindowController?

    func applicationWillFinishLaunching(_ notification: Notification) {
        UNUserNotificationCenter.current().delegate = notifications
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        let paths = ClaudePaths()
        let monitor = SessionMonitor(
            configuration: SessionMonitor.Configuration(paths: paths),
            processInspector: SystemProcessInspector(),
            notificationPoster: notifications,
            now: { Date() }
        )
        self.monitor = monitor

        let statusItemController = StatusItemController(
            monitor: monitor,
            launchAtLogin: launchAtLogin,
            openSession: { SessionOpener.open($0) }
        )
        self.statusItemController = statusItemController

        notifications.onOpenSession = { [weak monitor] id in
            SessionOpener.open(monitor?.openTarget(for: id) ?? SessionOpenTarget(sessionID: id, isArchived: false))
        }

        let driver = SessionRefreshDriver(directory: paths.sessionsDirectory) { [weak monitor, weak statusItemController] in
            guard let monitor else { return }
            monitor.refresh()
            statusItemController?.render(monitor.panelState)
        }
        self.driver = driver
        driver.start()

        notifications.requestAuthorization()
        showOnboardingIfNeeded()
    }

    func applicationWillTerminate(_ notification: Notification) {
        driver?.stop()
    }

    private func showOnboardingIfNeeded() {
        let key = "didShowOnboarding"
        guard !UserDefaults.standard.bool(forKey: key) else { return }
        UserDefaults.standard.set(true, forKey: key)
        let onboarding = OnboardingWindowController()
        self.onboarding = onboarding
        onboarding.show()
    }
}
