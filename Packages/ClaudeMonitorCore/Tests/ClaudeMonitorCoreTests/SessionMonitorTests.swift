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
        #expect(harness.monitor.panelState.icon.activity == .running(count: 1))
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

    @Test func recentlyFinishedShowsLatestTurnOncePerSession() throws {
        let harness = try MonitorHarness()
        try harness.writeSession("session-busy", pid: 100, status: "idle", at: 0)
        harness.refresh()
        try harness.completeTurn(pid: 100, from: 10, to: 23)
        try harness.completeTurn(pid: 100, from: 100, to: 372)

        let finished = harness.monitor.panelState.recentlyFinished

        #expect(finished.map(\.sessionID) == [busyID])
        #expect(finished.first?.duration == 272)
        #expect(finished.first?.endedAt == Fixture.date(372))
    }

    @Test func runningSessionLeavesRecentlyFinished() throws {
        let harness = try MonitorHarness()
        try harness.writeSession("session-busy", pid: 100, status: "idle", at: 0)
        harness.refresh()
        try harness.completeTurn(pid: 100, from: 10, to: 23)

        try harness.writeSession("session-busy", pid: 100, status: "busy", at: 50)
        harness.refresh()

        #expect(harness.monitor.panelState.running.map(\.id) == [busyID])
        #expect(harness.monitor.panelState.recentlyFinished.isEmpty)
    }

    @Test func unloadedMidTurnShowsPreviousTurnAgain() throws {
        let harness = try MonitorHarness()
        try harness.writeSession("session-busy", pid: 100, status: "idle", at: 0)
        harness.refresh()
        try harness.completeTurn(pid: 100, from: 10, to: 23)
        try harness.writeSession("session-busy", pid: 100, status: "busy", at: 50)
        harness.refresh()

        harness.processes.startTimes[100] = nil
        harness.refresh()

        #expect(harness.monitor.panelState.running.isEmpty)
        #expect(harness.monitor.panelState.recentlyFinished.map(\.duration) == [13])
    }

    @Test func recentlyFinishedKeepsTenNewestSessionsThatDoNotRun() throws {
        let harness = try MonitorHarness()
        let pids = (1...12).map { Int32(100 + $0) }
        for pid in pids {
            try harness.writeSession("session-busy", pid: pid, status: "idle", at: 0, overrides: ["hostSessionId": "local_session-\(pid)"])
        }
        harness.refresh()
        for (index, pid) in pids.enumerated() {
            let start = TimeInterval((index + 1) * 100)
            try harness.completeTurn(pid: pid, from: start, to: start + TimeInterval(index + 1), hostSessionId: "local_session-\(pid)")
        }

        for pid in pids.suffix(2) {
            try harness.writeSession("session-busy", pid: pid, status: "busy", at: 5000, overrides: ["hostSessionId": "local_session-\(pid)"])
        }
        harness.refresh()

        let finished = harness.monitor.panelState.recentlyFinished
        #expect(finished.map(\.sessionID.rawValue) == pids.prefix(10).reversed().map { "local_session-\($0)" })
        #expect(finished.map(\.duration) == (1...10).reversed().map { TimeInterval($0) })
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
        #expect(harness.monitor.panelState.icon.activity == .unsupported)
    }

    @Test func noWarningWhenOneFileHasKnownFormat() throws {
        let harness = try MonitorHarness()
        try harness.folder.writeRawSession(pid: 100, contents: Fixture.data("session-unsupported"))
        try harness.writeSession("session-idle", pid: 101, status: "idle", at: 0)

        harness.refresh()

        #expect(harness.monitor.panelState.formatWarning == nil)
        #expect(harness.monitor.panelState.icon.activity == .noSessions)
    }

    @Test func turnCompletesAfterPartialWriteRecovers() throws {
        let harness = try MonitorHarness()
        try harness.writeSession("session-busy", pid: 100, status: "idle", at: -60)
        harness.refresh()
        try harness.writeSession("session-busy", pid: 100, status: "busy", at: 0)
        harness.refresh()
        try harness.folder.writeRawSession(pid: 100, contents: Fixture.data("session-partial"))
        harness.refresh()

        try harness.writeSession("session-busy", pid: 100, status: "idle", at: 40)
        let events = harness.refresh()

        #expect(events == [SessionEvent(sessionID: busyID, kind: .turnCompleted(duration: 40))])
    }

    @Test func waitingToIdleCompletesTurn() throws {
        let harness = try MonitorHarness()
        try harness.writeSession("session-busy", pid: 100, status: "busy", at: 0)
        harness.refresh()
        try harness.writeSession(
            "session-busy", pid: 100, status: "waiting", at: 5,
            overrides: ["waitingFor": "input needed"]
        )
        harness.refresh()

        try harness.writeSession("session-busy", pid: 100, status: "idle", at: 20)
        let events = harness.refresh()

        #expect(events == [SessionEvent(sessionID: busyID, kind: .turnCompleted(duration: 20))])
    }

    @Test func deletedFileUnloadsRunningProcess() throws {
        let harness = try MonitorHarness()
        try harness.writeSession("session-busy", pid: 100, status: "busy", at: 0)
        harness.refresh()

        try harness.folder.removeSession(pid: 100)
        let events = harness.refresh()

        #expect(events == [SessionEvent(sessionID: busyID, kind: .unloaded)])
        #expect(harness.monitor.panelState.running.isEmpty)
    }

    @Test func unknownStatusThenIdleIsNotATurn() throws {
        let harness = try MonitorHarness()
        try harness.writeSession("session-busy", pid: 100, status: "compacting", at: 0)
        harness.refresh()

        try harness.writeSession("session-busy", pid: 100, status: "idle", at: 10)
        let events = harness.refresh()

        #expect(events.isEmpty)
        #expect(harness.notifications.posted.isEmpty)
    }

    @Test func busyWithNewerStatusTimeKeepsTurnStart() throws {
        let harness = try MonitorHarness()
        try harness.writeSession("session-busy", pid: 100, status: "busy", at: 10)
        harness.refresh()

        try harness.writeSession("session-busy", pid: 100, status: "busy", at: 50)
        let events = harness.refresh()

        #expect(events.isEmpty)
        #expect(harness.monitor.panelState.running.first?.turnStartedAt == Fixture.date(10))
    }

    @Test func spareConversionWithoutStatusShowsNoWarning() throws {
        let harness = try MonitorHarness()
        try harness.writeSession("session-spare", pid: 100)
        harness.refresh()

        try harness.writeSession("session-busy", pid: 100, overrides: ["status": NSNull(), "statusUpdatedAt": NSNull()])
        let events = harness.refresh()

        #expect(events.isEmpty)
        #expect(harness.monitor.panelState.formatWarning == nil)
        #expect(harness.monitor.panelState.icon.activity == .noSessions)
    }

    @Test func incompleteRewriteKeepsLastGoodSession() throws {
        let harness = try MonitorHarness()
        try harness.writeSession("session-busy", pid: 100, status: "busy", at: 0)
        harness.refresh()

        try harness.writeSession("session-busy", pid: 100, overrides: ["status": NSNull()])
        let events = harness.refresh()

        #expect(events.isEmpty)
        #expect(harness.monitor.panelState.running.map(\.id) == [busyID])
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

        #expect(harness.monitor.panelState.icon.activity == .waiting(runningCount: 2))
        #expect(harness.monitor.panelState.running.first?.id == SessionID(Fixture.waitingSessionID))
    }
}
