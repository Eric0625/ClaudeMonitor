import Foundation
@testable import ClaudeMonitorCore

final class FakeProcessInspector: ProcessInspector {
    var startTimes: [Int32: Date] = [:]

    func processStartTime(pid: Int32) -> Date? {
        startTimes[pid]
    }
}

final class RecordingNotificationPoster: NotificationPosting {
    private(set) var posted: [TurnNotification] = []

    func post(_ notification: TurnNotification) {
        posted.append(notification)
    }
}

final class TestClock {
    var now: Date

    init(now: Date) {
        self.now = now
    }
}

final class FrontmostState {
    var isClaudeFrontmost = false
}

/// A monitor that reads a fixture folder, with a fake process table and notification center.
@MainActor
final class MonitorHarness {
    let folder: FixtureFolder
    let processes = FakeProcessInspector()
    let notifications = RecordingNotificationPoster()
    let clock = TestClock(now: Fixture.baseTime)
    let frontmost = FrontmostState()
    let monitor: SessionMonitor

    var isClaudeFrontmost: Bool {
        get { frontmost.isClaudeFrontmost }
        set { frontmost.isClaudeFrontmost = newValue }
    }

    init(visibleSurfaces: Set<SessionSurface> = [.desktop]) throws {
        let folder = try FixtureFolder()
        self.folder = folder
        let clock = self.clock
        let frontmost = self.frontmost
        monitor = SessionMonitor(
            configuration: SessionMonitor.Configuration(
                sessionsDirectory: folder.sessionsDirectory,
                desktopSessionsDirectory: folder.desktopSessionsDirectory,
                visibleSurfaces: visibleSurfaces,
                metadataReloadInterval: 0
            ),
            processInspector: processes,
            notificationPoster: notifications,
            now: { clock.now },
            isClaudeFrontmost: { frontmost.isClaudeFrontmost }
        )
    }

    /// Writes the session file and marks its process as running.
    func writeSession(
        _ fixture: String,
        pid: Int32,
        status: String? = nil,
        at seconds: TimeInterval? = nil,
        overrides: [String: Any] = [:]
    ) throws {
        var values = overrides
        if let status {
            values["status"] = status
        }
        if let seconds {
            values["statusUpdatedAt"] = Fixture.epochMilliseconds(seconds)
            values["updatedAt"] = Fixture.epochMilliseconds(seconds)
        }
        if values["status"] != nil, values["status"] as? String != "waiting", values["waitingFor"] == nil {
            values["waitingFor"] = NSNull()
        }
        try folder.writeSession(fixture, pid: pid, overrides: values)
        processes.startTimes[pid] = Fixture.processStart
    }

    /// Writes `busy` at `start` and `idle` at `end`, with a read after each write.
    func completeTurn(pid: Int32, from start: TimeInterval, to end: TimeInterval, hostSessionId: String? = nil) throws {
        let overrides: [String: Any] = hostSessionId.map { ["hostSessionId": $0] } ?? [:]
        try writeSession("session-busy", pid: pid, status: "busy", at: start, overrides: overrides)
        refresh()
        try writeSession("session-busy", pid: pid, status: "idle", at: end, overrides: overrides)
        refresh()
    }

    @discardableResult
    func refresh(advancingClockBy seconds: TimeInterval = 1) -> [SessionEvent] {
        clock.now = clock.now.addingTimeInterval(seconds)
        return monitor.refresh()
    }
}
