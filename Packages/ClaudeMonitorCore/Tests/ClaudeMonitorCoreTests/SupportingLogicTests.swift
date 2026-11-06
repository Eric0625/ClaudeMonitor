import Foundation
import Testing
@testable import ClaudeMonitorCore

struct SessionOpenTargetTests {
    @Test func desktopSessionOpensWithDeepLink() {
        let target = SessionOpenTarget(sessionID: SessionID("local_4e4528cf-0000-4111-a026-d33f3d7bd507"), isArchived: false)

        #expect(target == .deepLink(URL(string: "claude://code/continue?session=local_4e4528cf-0000-4111-a026-d33f3d7bd507")!))
    }

    @Test(arguments: [
        "8acee975-0000-4301-902c-0c693e7cfc75",
        "pid-26719",
        "local_",
        "local_abc/def",
        "local_abc&x=1",
        "local_" + String(repeating: "a", count: 65),
    ])
    func invalidIdentifierActivatesClaude(raw: String) {
        #expect(SessionOpenTarget(sessionID: SessionID(raw), isArchived: false) == .activateClaude)
    }

    @Test func archivedSessionActivatesClaude() {
        let target = SessionOpenTarget(sessionID: SessionID("local_4e4528cf-0000-4111-a026-d33f3d7bd507"), isArchived: true)

        #expect(target == .activateClaude)
    }
}

struct TimeTextTests {
    @Test(arguments: [
        (0.0, "0s"),
        (0.6, "1s"),
        (45, "45s"),
        (95, "1m 35s"),
        (600, "10m 0s"),
        (3725, "1h 2m"),
        (-5, "0s"),
    ])
    func formatsDuration(seconds: TimeInterval, expected: String) {
        #expect(TimeText.duration(seconds) == expected)
    }

    @Test(arguments: [
        (3.0, "just now"),
        (45, "45s ago"),
        (95, "1m ago"),
        (7200, "2h ago"),
        (90000, "1d ago"),
    ])
    func formatsRelativeTime(secondsAgo: TimeInterval, expected: String) {
        let now = Fixture.baseTime

        #expect(TimeText.relative(from: now.addingTimeInterval(-secondsAgo), now: now) == expected)
    }
}

struct ClaudePathsTests {
    @Test func usesHomeFolderByDefault() {
        let home = URL(fileURLWithPath: "/Users/me", isDirectory: true)

        let paths = ClaudePaths(environment: [:], homeDirectory: home)

        #expect(paths.sessionsDirectory.path == "/Users/me/.claude/sessions")
        #expect(paths.desktopSessionsDirectory.path == "/Users/me/Library/Application Support/Claude/claude-code-sessions")
    }

    @Test func usesClaudeConfigDirWhenSet() {
        let home = URL(fileURLWithPath: "/Users/me", isDirectory: true)

        let paths = ClaudePaths(environment: ["CLAUDE_CONFIG_DIR": "/opt/claude"], homeDirectory: home)

        #expect(paths.sessionsDirectory.path == "/opt/claude/sessions")
    }
}

struct WaitingReasonTests {
    @Test func displayTextForKnownAndOtherReasons() {
        #expect(WaitingReason.inputNeeded.displayText == "Input needed")
        #expect(WaitingReason.goalProposal.displayText == "Goal proposal")
        #expect(WaitingReason.other("new reason").displayText == "new reason")
        #expect(WaitingReason.other("").displayText == "Waiting")
    }
}
