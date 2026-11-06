import Foundation

/// Keeps the records of running processes on visible surfaces, one record for each session.
struct LiveSessionFilter {
    let processInspector: ProcessInspector
    let visibleSurfaces: Set<SessionSurface>

    func liveSessions(from records: [SessionRecord]) -> [SessionID: SessionRecord] {
        var sessions: [SessionID: SessionRecord] = [:]
        for record in records where visibleSurfaces.contains(record.surface) && processInspector.isRunning(record) {
            if let existing = sessions[record.id], Self.isNewer(existing, than: record) {
                continue
            }
            sessions[record.id] = record
        }
        return sessions
    }

    private static func isNewer(_ lhs: SessionRecord, than rhs: SessionRecord) -> Bool {
        (lhs.statusUpdatedAt, lhs.processStartedAt, lhs.pid) > (rhs.statusUpdatedAt, rhs.processStartedAt, rhs.pid)
    }
}
