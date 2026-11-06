import Foundation
import Testing
@testable import ClaudeMonitorCore

struct SessionFileParserTests {
    @Test func parsesRealIdleFile() throws {
        let result = SessionFileParser.parse(try Fixture.data("session-idle"))

        guard case .session(let record) = result else {
            Issue.record("Expected a session, got \(result)")
            return
        }
        #expect(record.pid == 26719)
        #expect(record.processStartedAt == Fixture.processStart)
        #expect(record.id == SessionID(Fixture.idleSessionID))
        #expect(record.sessionId == "8acee975-0000-4301-902c-0c693e7cfc75")
        #expect(record.cwd == "/Users/me/code/project")
        #expect(record.name == "Fix card stop position")
        #expect(record.kind == "interactive")
        #expect(record.surface == .desktop)
        #expect(record.version == "2.1.317")
        #expect(record.status == .idle)
        #expect(record.statusUpdatedAt == Date(timeIntervalSince1970: 1_793_924_252.276))
    }

    @Test func parsesWaitingReason() throws {
        let result = SessionFileParser.parse(try Fixture.data("session-waiting"))

        guard case .session(let record) = result else {
            Issue.record("Expected a session, got \(result)")
            return
        }
        #expect(record.status == .waiting(.permissionPrompt))
    }

    @Test(arguments: [
        ("permission prompt", WaitingReason.permissionPrompt),
        ("input needed", .inputNeeded),
        ("dialog open", .dialogOpen),
        ("sandbox request", .sandboxRequest),
        ("goal proposal", .goalProposal),
        ("new reason", .other("new reason")),
    ])
    func mapsEveryWaitingReason(raw: String, expected: WaitingReason) throws {
        let data = try sessionData(overrides: ["status": "waiting", "waitingFor": raw])

        #expect(try record(from: data).status == .waiting(expected))
    }

    @Test func keepsUnknownStatusAsRawValue() throws {
        let data = try sessionData(overrides: ["status": "shell"])

        #expect(try record(from: data).status == .unknown("shell"))
    }

    @Test func fallsBackToSessionIdThenPidForIdentity() throws {
        let withoutHost = try sessionData(overrides: ["hostSessionId": NSNull()])
        let withoutEither = try sessionData(overrides: ["hostSessionId": NSNull(), "sessionId": NSNull()])

        #expect(try record(from: withoutHost).id == SessionID("8acee975-0000-4301-902c-0c693e7cfc75"))
        #expect(try record(from: withoutEither).id == SessionID("pid-26719"))
    }

    @Test(arguments: [
        ("claude-desktop", SessionSurface.desktop),
        ("claude-desktop-3p", .desktop),
        ("local-agent", .desktop),
        ("claude-vscode", .vsCode),
        ("cli", .terminal),
    ])
    func mapsEntrypointToSurface(entrypoint: String, expected: SessionSurface) throws {
        let data = try sessionData(overrides: ["entrypoint": entrypoint])

        #expect(try record(from: data).surface == expected)
    }

    @Test func parsesProcessStartWithTwoDigitDay() throws {
        let data = try sessionData(overrides: ["procStart": "Thu Nov 12 23:12:54 2026"])

        #expect(try record(from: data).processStartedAt == Fixture.processStart.addingTimeInterval(7 * 86400))
    }

    @Test func recognizesSpareRecord() throws {
        #expect(SessionFileParser.parse(try Fixture.data("session-spare")) == .spare)
    }

    @Test func reportsPartialJSONAsUnreadable() throws {
        #expect(SessionFileParser.parse(try Fixture.data("session-partial")) == .unreadable)
    }

    @Test func reportsUnknownLayoutAsUnsupportedWithVersion() throws {
        #expect(SessionFileParser.parse(try Fixture.data("session-unsupported")) == .unsupported(version: "3.0.0"))
    }

    @Test func reportsMissingRequiredFieldAsUnsupported() throws {
        let data = try sessionData(overrides: ["statusUpdatedAt": NSNull()])

        #expect(SessionFileParser.parse(data) == .unsupported(version: "2.1.317"))
    }

    @Test func reportsUnparsableProcessStartAsUnsupported() throws {
        let data = try sessionData(overrides: ["procStart": "2026-11-05T23:12:54Z"])

        #expect(SessionFileParser.parse(data) == .unsupported(version: "2.1.317"))
    }

    private func sessionData(overrides: [String: Any]) throws -> Data {
        var object = try Fixture.object("session-idle")
        for (key, value) in overrides {
            object[key] = value is NSNull ? nil : value
        }
        return try JSONSerialization.data(withJSONObject: object)
    }

    private func record(from data: Data) throws -> SessionRecord {
        guard case .session(let record) = SessionFileParser.parse(data) else {
            throw FixtureError.notAnObject("session")
        }
        return record
    }
}
