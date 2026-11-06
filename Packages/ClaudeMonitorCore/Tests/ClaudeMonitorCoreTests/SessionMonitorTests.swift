import Foundation
import Testing
@testable import ClaudeMonitorCore

@MainActor
struct SessionMonitorTests {
    private let busyID = SessionID(Fixture.busySessionID)

    @Test func newSessionAfterLaunchEmitsStartedAndRunning() throws {
        let harness = try MonitorHarness()
        harness.refresh()

        try harness.writeSession("session-busy", pid: 100, status: "busy", at: 0)
        let events = harness.refresh()

        #expect(events == [
            SessionEvent(sessionID: busyID, kind: .started),
            SessionEvent(sessionID: busyID, kind: .running),
        ])
        #expect(harness.monitor.panelState.icon == .running(count: 1))
    }

    @Test func replacedProcessDoesNotCompleteTurn() throws {
        let harness = try MonitorHarness()
        try harness.writeSession("session-busy", pid: 100, status: "busy", at: 0)
        harness.refresh()

        try harness.folder.removeSession(pid: 100)
        harness.processes.startTimes[100] = nil
        try harness.writeSession("session-busy", pid: 200, status: "idle", at: 30)
        let events = harness.refresh()

        #expect(!events.contains { if case .turnCompleted = $0.kind { true } else { false } })
        #expect(harness.notifications.posted.isEmpty)
        #expect(harness.monitor.panelState.running.isEmpty)
    }

    @Test func recentlyFinishedKeepsTenNewestFirst() throws {
        let harness = try MonitorHarness()
        try harness.writeSession("session-busy", pid: 100, status: "idle", at: 0)
        harness.refresh()

        for turn in 1...12 {
            let start = TimeInterval(turn * 100)
            try harness.writeSession("session-busy", pid: 100, status: "busy", at: start)
            harness.refresh()
            try harness.writeSession("session-busy", pid: 100, status: "idle", at: start + TimeInterval(turn))
            harness.refresh()
        }

        let finished = harness.monitor.panelState.recentlyFinished
        #expect(finished.count == 10)
        #expect(finished.map(\.duration) == (3...12).reversed().map { TimeInterval($0) })
        #expect(Set(finished.map(\.id)).count == 10)
    }

    @Test func hidesSurfacesThatAreNotVisible() throws {
        let harness = try MonitorHarness(visibleSurfaces: [.desktop])
        try harness.writeSession("session-terminal", pid: 100)
        try harness.writeSession("session-busy", pid: 101, status: "busy", at: 0)

        harness.refresh()

        #expect(harness.monitor.panelState.running.map(\.id) == [busyID])
    }

    @Test func showsWarningWhenNoFileHasKnownFormat() throws {
        let harness = try MonitorHarness()
        try harness.folder.writeRawSession(pid: 100, contents: Fixture.data("session-unsupported"))

        harness.refresh()

        #expect(harness.monitor.panelState.formatWarning == "Unsupported Claude Code session format (version 3.0.0)")
        #expect(harness.monitor.panelState.icon == .unsupported)
    }

    @Test func noWarningWhenOneFileHasKnownFormat() throws {
        let harness = try MonitorHarness()
        try harness.folder.writeRawSession(pid: 100, contents: Fixture.data("session-unsupported"))
        try harness.writeSession("session-idle", pid: 101, status: "idle", at: 0)

        harness.refresh()

        #expect(harness.monitor.panelState.formatWarning == nil)
        #expect(harness.monitor.panelState.icon == .noSessions)
    }

    @Test func ignoresKeyFilesAndMissingFolder() throws {
        let harness = try MonitorHarness()
        try harness.folder.writeFile(named: "100.cbf1fbbf.key", contents: Data("secret".utf8))
        harness.refresh()
        #expect(harness.monitor.panelState == PanelState.empty)

        try FileManager.default.removeItem(at: harness.folder.sessionsDirectory)
        harness.refresh()
        #expect(harness.monitor.panelState == PanelState.empty)
    }

    @Test func runningRowsShowFolderAndFallbackTitle() throws {
        let harness = try MonitorHarness()
        try harness.writeSession("session-busy", pid: 100, status: "busy", at: 0, overrides: ["name": NSNull()])

        harness.refresh()

        let row = try #require(harness.monitor.panelState.running.first)
        #expect(row.title == "menu-bar-app")
        #expect(row.folderName == "menu-bar-app")
        #expect(row.activity == .working)
    }

    @Test func archivedSessionOpensClaudeInsteadOfDeepLink() throws {
        let harness = try MonitorHarness()
        try harness.folder.writeDesktopMetadata(hostSessionId: Fixture.busySessionID, overrides: ["isArchived": true])
        try harness.writeSession("session-busy", pid: 100, status: "busy", at: 0)

        harness.refresh()

        #expect(harness.monitor.panelState.running.first?.openTarget == .activateClaude)
        #expect(harness.monitor.openTarget(for: busyID) == .activateClaude)
    }

    @Test func notificationUsesDesktopTitle() throws {
        let harness = try MonitorHarness()
        try harness.folder.writeDesktopMetadata(hostSessionId: Fixture.busySessionID, overrides: ["title": "Sidebar title"])
        try harness.writeSession("session-busy", pid: 100, status: "busy", at: 0)
        harness.refresh()

        try harness.writeSession("session-busy", pid: 100, status: "idle", at: 5)
        harness.refresh()

        #expect(harness.notifications.posted.map(\.body) == ["Sidebar title · 5s"])
    }

    @Test func waitingIconWinsOverRunningCount() throws {
        let harness = try MonitorHarness()
        try harness.writeSession("session-busy", pid: 100, status: "busy", at: 0)
        try harness.writeSession("session-waiting", pid: 101)

        harness.refresh()

        #expect(harness.monitor.panelState.icon == .waiting(runningCount: 2))
        #expect(harness.monitor.panelState.running.first?.id == SessionID(Fixture.waitingSessionID))
    }
}
