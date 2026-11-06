import Foundation
import Observation

/// Reads the session files, sends events to the store and notifications, and publishes the panel state.
@MainActor
@Observable
public final class SessionMonitor {
    public struct Configuration: Sendable {
        public var sessionsDirectory: URL
        public var desktopSessionsDirectory: URL
        public var visibleSurfaces: Set<SessionSurface>
        /// The maximum number of sessions in "Recently finished".
        public var recentlyFinishedLimit: Int
        /// The minimum time between two reads of the same desktop metadata file.
        public var metadataReloadInterval: TimeInterval

        public init(
            sessionsDirectory: URL,
            desktopSessionsDirectory: URL,
            visibleSurfaces: Set<SessionSurface> = [.desktop],
            recentlyFinishedLimit: Int = 10,
            metadataReloadInterval: TimeInterval = 5
        ) {
            self.sessionsDirectory = sessionsDirectory
            self.desktopSessionsDirectory = desktopSessionsDirectory
            self.visibleSurfaces = visibleSurfaces
            self.recentlyFinishedLimit = recentlyFinishedLimit
            self.metadataReloadInterval = metadataReloadInterval
        }

        public init(paths: ClaudePaths) {
            self.init(sessionsDirectory: paths.sessionsDirectory, desktopSessionsDirectory: paths.desktopSessionsDirectory)
        }
    }

    public private(set) var panelState = PanelState.empty

    @ObservationIgnored private let reader: SessionDirectoryReader
    @ObservationIgnored private let filter: LiveSessionFilter
    @ObservationIgnored private let store: SessionStore
    @ObservationIgnored private let metadataReader: DesktopMetadataReader
    @ObservationIgnored private let notificationService: NotificationService
    @ObservationIgnored private let recentlyFinishedLimit: Int

    public init(
        configuration: Configuration,
        processInspector: ProcessInspector,
        notificationPoster: NotificationPosting,
        now: @escaping @MainActor () -> Date
    ) {
        reader = SessionDirectoryReader(directory: configuration.sessionsDirectory)
        filter = LiveSessionFilter(processInspector: processInspector, visibleSurfaces: configuration.visibleSurfaces)
        store = SessionStore()
        recentlyFinishedLimit = configuration.recentlyFinishedLimit
        metadataReader = DesktopMetadataReader(
            rootDirectory: configuration.desktopSessionsDirectory,
            reloadInterval: configuration.metadataReloadInterval,
            now: { MainActor.assumeIsolated { now() } }
        )
        notificationService = NotificationService(poster: notificationPoster)
    }

    /// Reads all session files once. The first call is the baseline and shows no notification.
    @discardableResult
    public func refresh() -> [SessionEvent] {
        let scan = reader.read()
        let events = store.apply(filter.liveSessions(from: scan.records))
        notificationService.handle(events) { id in
            store.sessions[id].map { title(for: $0.record) } ?? id.rawValue
        }
        let nextState = makePanelState(formatSupport: scan.formatSupport)
        if nextState != panelState {
            panelState = nextState
        }
        return events
    }

    public func openTarget(for id: SessionID) -> SessionOpenTarget {
        SessionOpenTarget(sessionID: id, isArchived: metadataReader.metadata(for: id)?.isArchived ?? false)
    }

    private func makePanelState(formatSupport: SessionFormatSupport) -> PanelState {
        let running = store.sessions.values.compactMap(runningRow).sorted(by: Self.runningOrder)
        let runningIDs = Set(running.map(\.id))
        let finishedTurns = store.recentTurns.filter { !runningIDs.contains($0.sessionID) }.prefix(recentlyFinishedLimit)
        let finished = finishedTurns.map { turn in
            FinishedTurnRow(
                id: turn.sessionID.rawValue,
                sessionID: turn.sessionID,
                title: title(for: turn.record),
                folderName: turn.record.folderName,
                endedAt: turn.endedAt,
                duration: turn.duration,
                openTarget: openTarget(for: turn.sessionID)
            )
        }

        let icon: StatusIconState
        let formatWarning: String?
        switch formatSupport {
        case .unsupported(let version):
            icon = .unsupported
            formatWarning = "Unsupported Claude Code session format (version \(version ?? "unknown"))"
        case .supported:
            formatWarning = nil
            if running.contains(where: \.isWaiting) {
                icon = .waiting(runningCount: running.count)
            } else if !running.isEmpty {
                icon = .running(count: running.count)
            } else {
                icon = .noSessions
            }
        }
        return PanelState(running: running, recentlyFinished: finished, formatWarning: formatWarning, icon: icon)
    }

    private func runningRow(_ session: TrackedSession) -> RunningSessionRow? {
        let activity: RunningActivity
        switch session.record.status {
        case .idle: return nil
        case .busy: activity = .working
        case .waiting(let reason): activity = .waiting(reason)
        case .unknown(let raw): activity = .unrecognized(raw)
        }
        return RunningSessionRow(
            id: session.record.id,
            title: title(for: session.record),
            folderName: session.record.folderName,
            activity: activity,
            turnStartedAt: session.turnStartedAt,
            openTarget: openTarget(for: session.record.id)
        )
    }

    /// The desktop title, else the session name, else the folder name.
    private func title(for record: SessionRecord) -> String {
        let candidates = [metadataReader.metadata(for: record.id)?.title, record.name, record.folderName]
        return candidates.compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }.first { !$0.isEmpty }
            ?? "Untitled session"
    }

    private static func runningOrder(_ lhs: RunningSessionRow, _ rhs: RunningSessionRow) -> Bool {
        if lhs.isWaiting != rhs.isWaiting {
            return lhs.isWaiting
        }
        let lhsStart = lhs.turnStartedAt ?? .distantPast
        let rhsStart = rhs.turnStartedAt ?? .distantPast
        if lhsStart != rhsStart {
            return lhsStart > rhsStart
        }
        return lhs.id.rawValue < rhs.id.rawValue
    }
}
