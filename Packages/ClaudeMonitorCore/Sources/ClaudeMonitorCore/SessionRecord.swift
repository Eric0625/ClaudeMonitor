import Foundation

/// The identity of a session: `hostSessionId`, else `sessionId`, else the PID.
public struct SessionID: Hashable, Sendable, CustomStringConvertible {
    public let rawValue: String

    public init(_ rawValue: String) {
        self.rawValue = rawValue
    }

    public var description: String { rawValue }

    /// True for a desktop session ID such as `local_4e4528cf-...`.
    public var isDesktopSessionID: Bool {
        rawValue.wholeMatch(of: /local_[A-Za-z0-9-]{1,64}/) != nil
    }
}

/// The app that started a Claude Code process.
public enum SessionSurface: Hashable, Sendable, CaseIterable {
    case desktop
    case vsCode
    case terminal
}

/// One parsed `~/.claude/sessions/<pid>.json` file.
public struct SessionRecord: Equatable, Sendable {
    public var pid: Int32
    public var processStartedAt: Date
    public var sessionId: String?
    public var hostSessionId: String?
    public var cwd: String?
    public var name: String?
    public var kind: String?
    public var surface: SessionSurface
    public var version: String?
    public var status: SessionStatus
    public var statusUpdatedAt: Date

    public init(
        pid: Int32,
        processStartedAt: Date,
        sessionId: String?,
        hostSessionId: String?,
        cwd: String?,
        name: String?,
        kind: String?,
        surface: SessionSurface,
        version: String?,
        status: SessionStatus,
        statusUpdatedAt: Date
    ) {
        self.pid = pid
        self.processStartedAt = processStartedAt
        self.sessionId = sessionId
        self.hostSessionId = hostSessionId
        self.cwd = cwd
        self.name = name
        self.kind = kind
        self.surface = surface
        self.version = version
        self.status = status
        self.statusUpdatedAt = statusUpdatedAt
    }

    public var id: SessionID {
        if let hostSessionId, !hostSessionId.isEmpty {
            return SessionID(hostSessionId)
        }
        if let sessionId, !sessionId.isEmpty {
            return SessionID(sessionId)
        }
        return SessionID("pid-\(pid)")
    }

    /// Last path component of `cwd`.
    public var folderName: String {
        guard let cwd, !cwd.isEmpty else { return "" }
        return URL(fileURLWithPath: cwd).lastPathComponent
    }

    func isSameProcess(as other: SessionRecord) -> Bool {
        pid == other.pid && processStartedAt == other.processStartedAt
    }
}
