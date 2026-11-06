import Foundation

/// What a running session does now.
public enum RunningActivity: Equatable, Sendable {
    case working
    case waiting(WaitingReason)
    /// A `status` value that this version of the app does not know.
    case unrecognized(String)
}

public struct RunningSessionRow: Identifiable, Equatable, Sendable {
    public var id: SessionID
    public var title: String
    public var folderName: String
    public var activity: RunningActivity
    public var turnStartedAt: Date?
    public var openTarget: SessionOpenTarget

    /// The waiting reason, or the raw status value when the app does not know it.
    public var activityText: String? {
        switch activity {
        case .working: nil
        case .waiting(let reason): reason.displayText
        case .unrecognized(let raw): raw
        }
    }

    public var isWaiting: Bool {
        if case .waiting = activity { true } else { false }
    }
}

public struct FinishedTurnRow: Identifiable, Equatable, Sendable {
    public var id: String
    public var sessionID: SessionID
    public var title: String
    public var folderName: String
    public var endedAt: Date
    /// `nil` when the whole turn happened between two reads.
    public var duration: TimeInterval?
    public var openTarget: SessionOpenTarget
}

/// The menu bar icon states.
public enum StatusIconState: Equatable, Sendable {
    case noSessions
    case running(count: Int)
    case waiting(runningCount: Int)
    case unsupported
}

/// Everything that the menu bar icon and the panel show.
public struct PanelState: Equatable, Sendable {
    /// Sessions that are `busy`, `waiting`, or in an unknown status. Waiting sessions come first.
    public var running: [RunningSessionRow]
    /// The most recent completed turns, newest first.
    public var recentlyFinished: [FinishedTurnRow]
    /// Set when no session file has a known format.
    public var formatWarning: String?
    public var icon: StatusIconState

    public static let empty = PanelState(running: [], recentlyFinished: [], formatWarning: nil, icon: .noSessions)
}
