import Foundation

/// The result of parsing one session file.
public enum SessionFileParseResult: Equatable, Sendable {
    case session(SessionRecord)
    /// A pre-started spare process that has no session yet.
    case spare
    /// Valid JSON in a layout that this version of the app does not know.
    case unsupported(version: String?)
    /// Not a JSON object, for example a partial write.
    case unreadable
}

/// The only code that knows the JSON format of `~/.claude/sessions/<pid>.json`.
///
/// Verified with Claude Code 2.1.317. Anthropic does not document this format.
public enum SessionFileParser {
    public static func parse(_ data: Data) -> SessionFileParseResult {
        guard
            let json = try? JSONSerialization.jsonObject(with: data),
            let object = json as? [String: Any]
        else {
            return .unreadable
        }
        let version = object["version"] as? String

        if object["spare"] as? Bool == true {
            return .spare
        }

        guard
            let pid = int32(object["pid"]),
            let procStart = object["procStart"] as? String,
            let processStartedAt = parseProcessStart(procStart),
            let rawStatus = object["status"] as? String,
            let statusUpdatedAt = date(fromEpochMilliseconds: object["statusUpdatedAt"])
        else {
            return .unsupported(version: version)
        }

        return .session(SessionRecord(
            pid: pid,
            processStartedAt: processStartedAt,
            sessionId: object["sessionId"] as? String,
            hostSessionId: object["hostSessionId"] as? String,
            cwd: object["cwd"] as? String,
            name: object["name"] as? String,
            kind: object["kind"] as? String,
            surface: surface(forEntrypoint: object["entrypoint"] as? String),
            version: version,
            status: status(raw: rawStatus, waitingFor: object["waitingFor"] as? String),
            statusUpdatedAt: statusUpdatedAt
        ))
    }

    /// Parses `procStart`, which is UTC in the format of `ps -o lstart`, for example `Thu Nov  5 23:12:54 2026`.
    static func parseProcessStart(_ raw: String) -> Date? {
        let collapsed = raw.split(separator: " ", omittingEmptySubsequences: true).joined(separator: " ")
        return processStartFormatter.date(from: collapsed)
    }

    private static let processStartFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = "EEE MMM d HH:mm:ss yyyy"
        return formatter
    }()

    private static func status(raw: String, waitingFor: String?) -> SessionStatus {
        switch raw {
        case "busy": .busy
        case "idle": .idle
        case "waiting": .waiting(waitingReason(raw: waitingFor ?? ""))
        default: .unknown(raw)
        }
    }

    private static func waitingReason(raw: String) -> WaitingReason {
        switch raw {
        case "permission prompt": .permissionPrompt
        case "input needed": .inputNeeded
        case "dialog open": .dialogOpen
        case "sandbox request": .sandboxRequest
        case "goal proposal": .goalProposal
        default: .other(raw)
        }
    }

    private static func surface(forEntrypoint entrypoint: String?) -> SessionSurface {
        switch entrypoint {
        case "claude-desktop", "claude-desktop-3p", "local-agent": .desktop
        case "claude-vscode": .vsCode
        default: .terminal
        }
    }

    private static func int32(_ value: Any?) -> Int32? {
        guard let number = value as? NSNumber, !isBoolean(number) else { return nil }
        return Int32(exactly: number.int64Value)
    }

    private static func date(fromEpochMilliseconds value: Any?) -> Date? {
        guard let number = value as? NSNumber, !isBoolean(number) else { return nil }
        return Date(timeIntervalSince1970: number.doubleValue / 1000)
    }

    private static func isBoolean(_ number: NSNumber) -> Bool {
        CFGetTypeID(number) == CFBooleanGetTypeID()
    }
}
