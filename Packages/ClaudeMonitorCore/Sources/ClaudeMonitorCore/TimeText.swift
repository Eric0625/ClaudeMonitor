import Foundation

/// Short duration and relative time text for the panel and notifications.
public enum TimeText {
    /// For example `45s`, `1m 35s`, or `1h 2m`.
    public static func duration(_ seconds: TimeInterval) -> String {
        let total = max(0, Int(seconds.rounded()))
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let remainder = total % 60
        if hours > 0 {
            return "\(hours)h \(minutes)m"
        }
        if minutes > 0 {
            return "\(minutes)m \(remainder)s"
        }
        return "\(remainder)s"
    }

    /// For example `just now`, `45s ago`, `3m ago`, `2h ago`, or `1d ago`.
    public static func relative(from date: Date, now: Date) -> String {
        let elapsed = max(0, Int(now.timeIntervalSince(date)))
        switch elapsed {
        case ..<10: return "just now"
        case ..<60: return "\(elapsed)s ago"
        case ..<3600: return "\(elapsed / 60)m ago"
        case ..<86400: return "\(elapsed / 3600)h ago"
        default: return "\(elapsed / 86400)d ago"
        }
    }
}
