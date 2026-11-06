import Foundation

/// A change that the store found between two snapshots.
public struct SessionEvent: Equatable, Sendable {
    public enum Kind: Equatable, Sendable {
        case started
        case running
        case waiting(WaitingReason)
        /// `duration` is `nil` when the whole turn happened between two reads.
        case turnCompleted(duration: TimeInterval?)
        /// The process stopped. The desktop app also stops idle sessions that are not in focus.
        case unloaded
    }

    public var sessionID: SessionID
    public var kind: Kind

    public init(sessionID: SessionID, kind: Kind) {
        self.sessionID = sessionID
        self.kind = kind
    }
}

/// A live session and the start time of its current turn.
public struct TrackedSession: Equatable, Sendable {
    public var record: SessionRecord
    /// Time of the change from `idle` to `busy`. `nil` while no turn runs.
    public var turnStartedAt: Date?
}

public struct CompletedTurn: Equatable, Sendable {
    public var record: SessionRecord
    public var endedAt: Date
    public var duration: TimeInterval?

    public var sessionID: SessionID { record.id }
}

/// The only owner of session state transitions.
public final class SessionStore {
    public private(set) var sessions: [SessionID: TrackedSession] = [:]
    /// The latest completed turn of each session, newest first.
    public private(set) var recentTurns: [CompletedTurn] = []

    private var hasBaseline = false

    public init() {}

    /// Compares the snapshot with the previous one. The first snapshot is the baseline and emits no events.
    @discardableResult
    public func apply(_ snapshot: [SessionID: SessionRecord]) -> [SessionEvent] {
        defer { hasBaseline = true }
        var events: [SessionEvent] = []
        var next: [SessionID: TrackedSession] = [:]

        for (id, record) in snapshot.sorted(by: { $0.key.rawValue < $1.key.rawValue }) {
            if let previous = sessions[id] {
                let (tracked, transitionEvents) = transition(from: previous, to: record)
                next[id] = tracked
                events += transitionEvents
            } else {
                next[id] = TrackedSession(record: record, turnStartedAt: Self.isTurnActive(record.status) ? record.statusUpdatedAt : nil)
                if hasBaseline {
                    events.append(SessionEvent(sessionID: id, kind: .started))
                    events += Self.statusEvent(for: record).map { [$0] } ?? []
                }
            }
        }

        for id in sessions.keys.sorted(by: { $0.rawValue < $1.rawValue }) where snapshot[id] == nil {
            events.append(SessionEvent(sessionID: id, kind: .unloaded))
        }

        sessions = next
        return hasBaseline ? events : []
    }

    private func transition(from previous: TrackedSession, to record: SessionRecord) -> (TrackedSession, [SessionEvent]) {
        let old = previous.record
        let id = record.id

        guard old.isSameProcess(as: record) else {
            let tracked = TrackedSession(record: record, turnStartedAt: Self.isTurnActive(record.status) ? record.statusUpdatedAt : nil)
            let events = record.status == old.status ? [] : Self.statusEvent(for: record).map { [$0] } ?? []
            return (tracked, events)
        }

        let statusChanged = record.status != old.status
        let isNewWrite = record.statusUpdatedAt > old.statusUpdatedAt

        switch record.status {
        case .idle:
            if previous.turnStartedAt != nil || (old.status == .idle && isNewWrite) {
                let duration = previous.turnStartedAt.map { max(0, record.statusUpdatedAt.timeIntervalSince($0)) }
                completeTurn(record: record, duration: duration)
                return (
                    TrackedSession(record: record, turnStartedAt: nil),
                    [SessionEvent(sessionID: id, kind: .turnCompleted(duration: duration))]
                )
            }
            return (TrackedSession(record: record, turnStartedAt: nil), [])

        case .busy, .waiting:
            let turnStartedAt = previous.turnStartedAt ?? record.statusUpdatedAt
            let events = statusChanged ? Self.statusEvent(for: record).map { [$0] } ?? [] : []
            return (TrackedSession(record: record, turnStartedAt: turnStartedAt), events)

        case .unknown:
            return (TrackedSession(record: record, turnStartedAt: previous.turnStartedAt), [])
        }
    }

    private func completeTurn(record: SessionRecord, duration: TimeInterval?) {
        recentTurns.removeAll { $0.sessionID == record.id }
        recentTurns.insert(CompletedTurn(record: record, endedAt: record.statusUpdatedAt, duration: duration), at: 0)
    }

    private static func isTurnActive(_ status: SessionStatus) -> Bool {
        switch status {
        case .busy, .waiting: true
        case .idle, .unknown: false
        }
    }

    private static func statusEvent(for record: SessionRecord) -> SessionEvent? {
        switch record.status {
        case .busy: SessionEvent(sessionID: record.id, kind: .running)
        case .waiting(let reason): SessionEvent(sessionID: record.id, kind: .waiting(reason))
        case .idle, .unknown: nil
        }
    }
}
