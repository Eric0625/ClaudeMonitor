import Foundation

/// The content of one macOS notification.
public struct TurnNotification: Equatable, Sendable {
    public var title: String
    public var body: String
    /// Goes into `userInfo` so that a click can open the session.
    public var hostSessionId: String

    public init(title: String, body: String, hostSessionId: String) {
        self.title = title
        self.body = body
        self.hostSessionId = hostSessionId
    }
}

/// Shows notifications. The app uses `UNUserNotificationCenter`. Tests record the requests.
@MainActor
public protocol NotificationPosting {
    func post(_ notification: TurnNotification)
}

/// Turns store events into notifications.
@MainActor
public struct NotificationService {
    public nonisolated static let turnCompletedTitle = "Turn completed"
    public nonisolated static let hostSessionIdKey = "hostSessionId"

    private let poster: NotificationPosting

    public init(poster: NotificationPosting) {
        self.poster = poster
    }

    func handle(_ events: [SessionEvent], title: (SessionID) -> String) {
        for event in events {
            guard case .turnCompleted(let duration) = event.kind else { continue }
            let sessionTitle = title(event.sessionID)
            let body = duration.map { "\(sessionTitle) · \(TimeText.duration($0))" } ?? sessionTitle
            poster.post(TurnNotification(
                title: Self.turnCompletedTitle,
                body: body,
                hostSessionId: event.sessionID.rawValue
            ))
        }
    }
}
