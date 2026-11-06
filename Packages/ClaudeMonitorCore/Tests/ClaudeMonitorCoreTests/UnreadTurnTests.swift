import Foundation
import Testing
@testable import ClaudeMonitorCore

@MainActor
struct UnreadTurnTests {
    private let busyID = SessionID(Fixture.busySessionID)

    private func harnessWithFinishedTurn(endingAt end: TimeInterval = 95) throws -> MonitorHarness {
        let harness = try MonitorHarness()
        try harness.writeSession("session-busy", pid: 100, status: "idle", at: -60)
        harness.refresh()
        try harness.completeTurn(pid: 100, from: 0, to: end)
        return harness
    }

    private func isUnread(_ harness: MonitorHarness) -> Bool? {
        harness.monitor.panelState.recentlyFinished.first { $0.sessionID == busyID }?.isUnread
    }

    @Test func turnWithoutFocusTimeIsUnread() throws {
        let harness = try harnessWithFinishedTurn()
        try harness.folder.writeDesktopMetadata(hostSessionId: Fixture.busySessionID, overrides: ["lastFocusedAt": NSNull()])
        harness.refresh()

        #expect(isUnread(harness) == true)
    }

    @Test func turnWithoutDesktopMetadataIsUnread() throws {
        let harness = try harnessWithFinishedTurn()

        #expect(isUnread(harness) == true)
    }

    @Test func turnFocusedInClaudeBeforeItEndedIsUnread() throws {
        let harness = try harnessWithFinishedTurn()
        try harness.folder.writeDesktopMetadata(
            hostSessionId: Fixture.busySessionID,
            overrides: ["lastFocusedAt": Fixture.epochMilliseconds(50)]
        )
        harness.refresh()

        #expect(isUnread(harness) == true)
    }

    @Test func turnFocusedInClaudeAfterItEndedIsRead() throws {
        let harness = try harnessWithFinishedTurn()
        try harness.folder.writeDesktopMetadata(
            hostSessionId: Fixture.busySessionID,
            overrides: ["lastFocusedAt": Fixture.epochMilliseconds(120)]
        )
        harness.refresh()

        #expect(isUnread(harness) == false)
    }

    @Test func openingFromPanelMarksTurnReadAtOnce() throws {
        let harness = try harnessWithFinishedTurn()
        #expect(isUnread(harness) == true)

        harness.monitor.markViewed(busyID)

        #expect(isUnread(harness) == false)
    }

    @Test func turnEndingInFocusedSessionWhileClaudeIsFrontmostIsRead() throws {
        let harness = try MonitorHarness()
        try harness.writeSession("session-busy", pid: 100, status: "idle", at: -60)
        try harness.folder.writeDesktopMetadata(
            hostSessionId: Fixture.busySessionID,
            overrides: ["lastFocusedAt": Fixture.epochMilliseconds(-10)]
        )
        harness.refresh()
        harness.isClaudeFrontmost = true

        try harness.completeTurn(pid: 100, from: 0, to: 95)

        #expect(isUnread(harness) == false)
    }

    @Test func turnEndingWhileClaudeIsNotFrontmostIsUnread() throws {
        let harness = try MonitorHarness()
        try harness.writeSession("session-busy", pid: 100, status: "idle", at: -60)
        try harness.folder.writeDesktopMetadata(
            hostSessionId: Fixture.busySessionID,
            overrides: ["lastFocusedAt": Fixture.epochMilliseconds(-10)]
        )
        harness.refresh()
        harness.isClaudeFrontmost = false

        try harness.completeTurn(pid: 100, from: 0, to: 95)

        #expect(isUnread(harness) == true)
    }

    @Test func turnEndingWhileOtherSessionIsFocusedIsUnread() throws {
        let harness = try MonitorHarness()
        let otherID = "local_other-session"
        try harness.writeSession("session-busy", pid: 100, status: "idle", at: -60)
        try harness.writeSession("session-busy", pid: 101, status: "idle", at: -60, overrides: ["hostSessionId": otherID])
        try harness.folder.writeDesktopMetadata(
            hostSessionId: Fixture.busySessionID,
            overrides: ["lastFocusedAt": Fixture.epochMilliseconds(-10)]
        )
        try harness.folder.writeDesktopMetadata(
            hostSessionId: otherID,
            overrides: ["lastFocusedAt": Fixture.epochMilliseconds(-5)]
        )
        harness.refresh()
        harness.isClaudeFrontmost = true

        try harness.completeTurn(pid: 100, from: 0, to: 95)

        #expect(isUnread(harness) == true)
    }

    @Test func turnEndingInSessionNeverFocusedIsUnread() throws {
        let harness = try MonitorHarness()
        try harness.writeSession("session-busy", pid: 100, status: "idle", at: -60)
        try harness.folder.writeDesktopMetadata(hostSessionId: Fixture.busySessionID, overrides: ["lastFocusedAt": NSNull()])
        harness.refresh()
        harness.isClaudeFrontmost = true

        try harness.completeTurn(pid: 100, from: 0, to: 95)

        #expect(isUnread(harness) == true)
    }

    @Test func newTurnAfterViewIsUnreadAgain() throws {
        let harness = try harnessWithFinishedTurn()
        harness.monitor.markViewed(busyID)

        try harness.completeTurn(pid: 100, from: 200, to: 260)

        #expect(isUnread(harness) == true)
    }
}
