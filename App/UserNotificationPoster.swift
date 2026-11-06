import ClaudeMonitorCore
import Foundation
import os
import UserNotifications

/// Shows turn notifications with `UNUserNotificationCenter` and opens the session on a click.
@MainActor
final class UserNotificationPoster: NSObject, NotificationPosting, UNUserNotificationCenterDelegate {
    var onOpenSession: ((SessionID) -> Void)?

    private let logger = Logger(subsystem: "com.ericyuan.ClaudeMonitor", category: "notifications")

    func requestAuthorization() {
        let logger = logger
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, error in
            if let error {
                logger.error("Notification authorization failed: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    func post(_ notification: TurnNotification) {
        let content = UNMutableNotificationContent()
        content.title = notification.title
        content.body = notification.body
        content.sound = .default
        content.threadIdentifier = notification.hostSessionId
        content.userInfo = [NotificationService.hostSessionIdKey: notification.hostSessionId]

        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        let logger = logger
        UNUserNotificationCenter.current().add(request) { error in
            if let error {
                logger.error("Notification request failed: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let userInfo = response.notification.request.content.userInfo
        let hostSessionId = userInfo[NotificationService.hostSessionIdKey] as? String
        if response.actionIdentifier == UNNotificationDefaultActionIdentifier, let hostSessionId {
            Task { @MainActor in
                self.onOpenSession?(SessionID(hostSessionId))
            }
        }
        completionHandler()
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .list, .sound])
    }
}
