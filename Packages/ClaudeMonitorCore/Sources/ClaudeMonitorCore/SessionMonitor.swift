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
    @ObservationIgnored private let isClaudeFrontmost: @MainActor () -> Bool
    @ObservationIgnored private var formatSupport = SessionFormatSupport.supported
    /// The end time of the latest turn that the user saw, for each session.
    @ObservationIgnored private var viewedTurnEnds: [SessionID: Date] = [:]

    public init(
        configuration: Configuration,
        processInspector: ProcessInspector,
        notificationPoster: NotificationPosting,
        now: @escaping @MainActor () -> Date,
        isClaudeFrontmost: @escaping @MainActor () -> Bool
    ) {
        self.isClaudeFrontmost = isClaudeFrontmost
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
        markTurnsSeenAsTheyEnded(events)
        notificationService.handle(events) { id in
            store.sessions[id].map { title(for: $0.record) } ?? id.rawValue
        }
        formatSupport = scan.formatSupport
        publishPanelState()
        return events
    }

    /// Marks the latest finished turn of the session as read. Call it when the user opens the session from this app.
    public func markViewed(_ id: SessionID) {
        guard let turn = store.recentTurns.first(where: { $0.sessionID == id }) else { return }
        viewedTurnEnds[id] = turn.endedAt
        publishPanelState()
    }

    public func openTarget(for id: SessionID) -> SessionOpenTarget {
        SessionOpenTarget(sessionID: id, isArchived: metadataReader.metadata(for: id)?.isArchived ?? false)
    }

    /// A turn that ends in the session that Claude shows in front is read.
    private func markTurnsSeenAsTheyEnded(_ events: [SessionEvent]) {
        let completedIDs = events.compactMap { event -> SessionID? in
            if case .turnCompleted = event.kind { event.sessionID } else { nil }
        }
        guard !completedIDs.isEmpty, isClaudeFrontmost(), let focusedID = focusedSessionID() else { return }
        for id in completedIDs where id == focusedID {
            if let turn = store.recentTurns.first(where: { $0.sessionID == id }) {
                viewedTurnEnds[id] = turn.endedAt
            }
        }
    }

    /// The live session with the newest `lastFocusedAt`.
    private func focusedSessionID() -> SessionID? {
        store.sessions.keys
            .compactMap { id in metadataReader.metadata(for: id)?.lastFocusedAt.map { (id, $0) } }
            .max { $0.1 < $1.1 }?
            .0
    }

    private func publishPanelState() {
        let nextState = makePanelState()
        if nextState != panelState {
            panelState = nextState
        }
    }

    private func makePanelState() -> PanelState {
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
                isUnread: isUnread(turn),
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

    private func isUnread(_ turn: CompletedTurn) -> Bool {
        let viewedAt = [metadataReader.metadata(for: turn.sessionID)?.lastFocusedAt, viewedTurnEnds[turn.sessionID]]
            .compactMap { $0 }
            .max()
        guard let viewedAt else { return true }
        return viewedAt < turn.endedAt
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
