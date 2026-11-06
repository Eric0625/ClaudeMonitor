import Foundation

/// The folders that Claude Code and the Claude app write.
public struct ClaudePaths: Sendable {
    /// `$CLAUDE_CONFIG_DIR/sessions`, else `~/.claude/sessions`.
    public var sessionsDirectory: URL
    /// `~/Library/Application Support/Claude/claude-code-sessions`.
    public var desktopSessionsDirectory: URL

    public init(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser
    ) {
        let configDirectory: URL
        if let custom = environment["CLAUDE_CONFIG_DIR"], !custom.isEmpty {
            configDirectory = URL(fileURLWithPath: (custom as NSString).expandingTildeInPath, isDirectory: true)
        } else {
            configDirectory = homeDirectory.appendingPathComponent(".claude", isDirectory: true)
        }
        sessionsDirectory = configDirectory.appendingPathComponent("sessions", isDirectory: true)
        desktopSessionsDirectory = homeDirectory
            .appendingPathComponent("Library/Application Support/Claude/claude-code-sessions", isDirectory: true)
    }
}
