import Foundation

/// How a click on a session opens it in the Claude app.
public enum SessionOpenTarget: Equatable, Sendable {
    /// `claude://code/continue?session=<hostSessionId>`.
    case deepLink(URL)
    /// Bring the Claude app to the front. The deep link does not find archived sessions or non-desktop IDs.
    case activateClaude

    public static let claudeBundleIdentifier = "com.anthropic.claudefordesktop"

    public init(sessionID: SessionID, isArchived: Bool) {
        guard
            !isArchived,
            sessionID.isDesktopSessionID,
            let url = URL(string: "claude://code/continue?session=\(sessionID.rawValue)")
        else {
            self = .activateClaude
            return
        }
        self = .deepLink(url)
    }
}
