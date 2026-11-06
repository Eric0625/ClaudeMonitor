import Foundation
import Testing
@testable import ClaudeMonitorCore

@MainActor
struct BehaviorScenarioTests {
    private let busyID = SessionID(Fixture.busySessionID)

    // MARK: 1

    @Test func busyToIdleCompletesTurnWithOneNotification() throws {
        let harness = try MonitorHarness()
        try harness.writeSession("session-busy", pid: 100, status: "idle", at: -60)
        harness.refresh()
        try harness.writeSession("session-busy", pid: 100, status: "busy", at: 0)
        harness.refresh()

        try harness.writeSession("session-busy", pid: 100, status: "idle", at: 95)
        let events = harness.refresh()

        #expect(events == [SessionEvent(sessionID: busyID, kind: .turnCompleted(duration: 95))])
        #expect(harness.notifications.posted == [
            TurnNotification(
                title: "Turn completed",
                body: "Build menu bar app · 1m 35s",
                hostSessionId: Fixture.busySessionID
            ),
        ])
        #expect(harness.monitor.panelState.running.isEmpty)
        #expect(harness.monitor.panelState.recentlyFinished.map(\.sessionID) == [busyID])
        #expect(harness.monitor.panelState.recentlyFinished.first?.duration == 95)
        #expect(harness.monitor.panelState.recentlyFinished.first?.endedAt == Fixture.date(95))
    }

    // MARK: 2

    @Test func idleWithNewerStatusTimeCompletesTurn() throws {
        let harness = try MonitorHarness()
        try harness.writeSession("session-busy", pid: 100, status: "idle", at: 0)
        harness.refresh()

        try harness.writeSession("session-busy", pid: 100, status: "idle", at: 30)
        let events = harness.refresh()

        #expect(events == [SessionEvent(sessionID: busyID, kind: .turnCompleted(duration: nil))])
        #expect(harness.notifications.posted.count == 1)
        #expect(harness.monitor.panelState.recentlyFinished.map(\.sessionID) == [busyID])
    }

    // MARK: 3

    @Test func busyToWaitingStaysRunningWithReasonAndNoNotification() throws {
        let harness = try MonitorHarness()
        try harness.writeSession("session-busy", pid: 100, status: "idle", at: -60)
        harness.refresh()
        try harness.writeSession("session-busy", pid: 100, status: "busy", at: 0)
        harness.refresh()

        try harness.writeSession(
            "session-busy", pid: 100, status: "waiting", at: 10,
            overrides: ["waitingFor": "permission prompt"]
        )
        let events = harness.refresh()

        #expect(events == [SessionEvent(sessionID: busyID, kind: .waiting(.permissionPrompt))])
        let row = try #require(harness.monitor.panelState.running.first)
        #expect(harness.monitor.panelState.running.count == 1)
        #expect(row.id == busyID)
        #expect(row.activity == .waiting(.permissionPrompt))
        #expect(row.activityText == "Permission prompt")
        #expect(row.turnStartedAt == Fixture.date(0))
        #expect(harness.notifications.posted.isEmpty)
        #expect(harness.monitor.panelState.icon == .waiting(runningCount: 1))
    }

    // MARK: 4

    @Test func turnDurationStartsAtFirstBusyAfterWaitingRoundTrip() throws {
        let harness = try MonitorHarness()
        try harness.writeSession("session-busy", pid: 100, status: "idle", at: -60)
        harness.refresh()
        try harness.writeSession("session-busy", pid: 100, status: "busy", at: 0)
        harness.refresh()
        try harness.writeSession(
            "session-busy", pid: 100, status: "waiting", at: 10,
            overrides: ["waitingFor": "permission prompt"]
        )
        harness.refresh()
        try harness.writeSession("session-busy", pid: 100, status: "busy", at: 40)
        let resumeEvents = harness.refresh()

        try harness.writeSession("session-busy", pid: 100, status: "idle", at: 100)
        let events = harness.refresh()

        #expect(resumeEvents == [SessionEvent(sessionID: busyID, kind: .running)])
        #expect(events == [SessionEvent(sessionID: busyID, kind: .turnCompleted(duration: 100))])
    }

    // MARK: 5

    @Test func firstReadAtLaunchShowsNoNotification() throws {
        let harness = try MonitorHarness()
        try harness.writeSession("session-idle", pid: 100, status: "idle", at: 0)
        try harness.writeSession("session-busy", pid: 101, status: "busy", at: 0)

        let events = harness.refresh()

        #expect(events.isEmpty)
        #expect(harness.notifications.posted.isEmpty)
        #expect(harness.monitor.panelState.running.map(\.id) == [busyID])
        #expect(harness.monitor.panelState.recentlyFinished.isEmpty)
    }

    // MARK: 6

    @Test func sessionWithoutMatchingProcessIsNotListed() throws {
        let harness = try MonitorHarness()
        try harness.writeSession("session-busy", pid: 100, status: "busy", at: 0)
        harness.processes.startTimes[100] = nil
        try harness.writeSession("session-waiting", pid: 101, status: "busy", at: 0)
        harness.processes.startTimes[101] = Fixture.processStart.addingTimeInterval(3600)
        try harness.writeSession("session-idle", pid: 102, status: "busy", at: 0)

        harness.refresh()

        #expect(harness.monitor.panelState.running.map(\.id) == [SessionID(Fixture.idleSessionID)])
    }

    // MARK: 7

    @Test func partialJSONKeepsLastGoodStateWithoutEvents() throws {
        let harness = try MonitorHarness()
        try harness.writeSession("session-busy", pid: 100, status: "idle", at: -60)
        harness.refresh()
        try harness.writeSession("session-busy", pid: 100, status: "busy", at: 0)
        harness.refresh()

        try harness.folder.writeRawSession(pid: 100, contents: Fixture.data("session-partial"))
        let events = harness.refresh()

        #expect(events.isEmpty)
        #expect(harness.monitor.panelState.running.map(\.id) == [busyID])
        #expect(harness.monitor.panelState.formatWarning == nil)
        #expect(harness.notifications.posted.isEmpty)
    }

    // MARK: 8

    @Test func spareRecordIsNotListed() throws {
        let harness = try MonitorHarness()
        try harness.writeSession("session-spare", pid: 100)
        try harness.writeSession("session-busy", pid: 101, status: "busy", at: 0)

        harness.refresh()

        #expect(harness.monitor.panelState.running.map(\.id) == [busyID])
        #expect(harness.monitor.panelState.formatWarning == nil)
    }

    // MARK: 9

    @Test func duplicateHostSessionUsesNewestStatusTime() throws {
        let harness = try MonitorHarness()
        try harness.writeSession("session-busy", pid: 100, status: "busy", at: 50)
        try harness.writeSession("session-busy", pid: 101, status: "idle", at: 20)
        harness.refresh()
        #expect(harness.monitor.panelState.running.map(\.id) == [busyID])
        #expect(harness.monitor.panelState.running.first?.turnStartedAt == Fixture.date(50))

        let otherHarness = try MonitorHarness()
        try otherHarness.writeSession("session-busy", pid: 100, status: "busy", at: 20)
        try otherHarness.writeSession("session-busy", pid: 101, status: "idle", at: 50)
        otherHarness.refresh()
        #expect(otherHarness.monitor.panelState.running.isEmpty)
    }

    // MARK: 10

    @Test func desktopTitleReplacesSessionName() throws {
        let harness = try MonitorHarness()
        try harness.folder.writeDesktopMetadata(
            hostSessionId: Fixture.busySessionID,
            overrides: ["title": "Renamed in sidebar"]
        )
        try harness.writeSession("session-busy", pid: 100, status: "busy", at: 0)

        harness.refresh()

        #expect(harness.monitor.panelState.running.first?.title == "Renamed in sidebar")
    }

    // MARK: 11

    @Test(arguments: [ProcessStop.crashLeavesFile, .normalExitRemovesFile])
    func stoppedProcessUnloadsWithoutTurnCompleted(_ stop: ProcessStop) throws {
        let harness = try MonitorHarness()
        try harness.writeSession("session-busy", pid: 100, status: "idle", at: -60)
        harness.refresh()
        try harness.writeSession("session-busy", pid: 100, status: "busy", at: 0)
        harness.refresh()

        harness.processes.startTimes[100] = nil
        if stop == .normalExitRemovesFile {
            try harness.folder.removeSession(pid: 100)
        }
        let events = harness.refresh()

        #expect(events == [SessionEvent(sessionID: busyID, kind: .unloaded)])
        #expect(harness.monitor.panelState.running.isEmpty)
        #expect(harness.monitor.panelState.recentlyFinished.isEmpty)
        #expect(harness.notifications.posted.isEmpty)
    }

    // MARK: 12

    @Test func unknownStatusShowsRawValue() throws {
        let harness = try MonitorHarness()
        try harness.writeSession("session-unknown-status", pid: 100)

        harness.refresh()

        let row = try #require(harness.monitor.panelState.running.first)
        #expect(row.id == SessionID(Fixture.unknownStatusSessionID))
        #expect(row.activity == .unrecognized("compacting"))
        #expect(row.activityText == "compacting")
        #expect(harness.monitor.panelState.formatWarning == nil)
    }

    enum ProcessStop: CustomTestStringConvertible {
        case crashLeavesFile
        case normalExitRemovesFile

        var testDescription: String {
            switch self {
            case .crashLeavesFile: "crash leaves file"
            case .normalExitRemovesFile: "normal exit removes file"
            }
        }
    }
}
