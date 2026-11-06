import Darwin
import Foundation
import Testing
@testable import ClaudeMonitorCore

struct SystemProcessInspectorTests {
    @Test func startTimeOfThisProcessMatchesPsInUTC() throws {
        let pid = getpid()
        let procStart = try psStartTimeInUTC(pid: pid)
        let parsed = try #require(SessionFileParser.parseProcessStart(procStart))

        let startTime = try #require(SystemProcessInspector().processStartTime(pid: pid))

        #expect(Int64(startTime.timeIntervalSince1970) == Int64(parsed.timeIntervalSince1970))
    }

    @Test func missingProcessHasNoStartTime() {
        #expect(SystemProcessInspector().processStartTime(pid: Int32.max) == nil)
    }

    /// `ps -o lstart` in UTC, the format that Claude Code writes to `procStart`.
    private func psStartTimeInUTC(pid: Int32) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/ps")
        process.arguments = ["-o", "lstart=", "-p", "\(pid)"]
        process.environment = ["TZ": "UTC", "LC_ALL": "C"]
        let pipe = Pipe()
        process.standardOutput = pipe
        try process.run()
        process.waitUntilExit()
        let output = String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        return output.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
