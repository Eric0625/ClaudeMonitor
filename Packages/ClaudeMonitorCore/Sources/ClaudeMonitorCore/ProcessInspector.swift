import Darwin
import Foundation

/// The liveness check for a session file.
public protocol ProcessInspector {
    /// The start time of the process, or `nil` when no such process exists.
    func processStartTime(pid: Int32) -> Date?
}

extension ProcessInspector {
    /// True when the process runs and started at the time that the session file records.
    func isRunning(_ record: SessionRecord) -> Bool {
        guard let startTime = processStartTime(pid: record.pid) else { return false }
        return wholeSeconds(startTime) == wholeSeconds(record.processStartedAt)
    }

    private func wholeSeconds(_ date: Date) -> Int64 {
        Int64(date.timeIntervalSince1970.rounded(.down))
    }
}

/// Reads process start times from the kernel with `proc_pidinfo`.
public struct SystemProcessInspector: ProcessInspector {
    public init() {}

    public func processStartTime(pid: Int32) -> Date? {
        var info = proc_bsdinfo()
        let size = Int32(MemoryLayout<proc_bsdinfo>.size)
        guard proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, size) == size else { return nil }
        return Date(timeIntervalSince1970: TimeInterval(info.pbi_start_tvsec))
    }
}
