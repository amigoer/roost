import Foundation

/// One quota window, as Claude Code reports it to a status line.
public struct UsageWindow: Codable, Sendable, Hashable {
    /// How much of the window is spent, 0-1.
    public let used: Double
    /// When it empties again, when the payload says.
    public let resetsAt: Date?

    public init(used: Double, resetsAt: Date? = nil) {
        self.used = min(max(used, 0), 1)
        self.resetsAt = resetsAt
    }

    public func remaining(now: Date = Date()) -> TimeInterval? {
        guard let resetsAt else { return nil }
        return max(0, resetsAt.timeIntervalSince(now))
    }
}

/// What is left of the account's quota, and of the session's context.
///
/// Account-wide rather than per session: every session on this Mac spends the
/// same five-hour window, so the island reports it once for the whole fleet.
public struct Usage: Codable, Sendable, Hashable {
    public let fiveHour: UsageWindow?
    public let sevenDay: UsageWindow?
    public let reportedAt: Date

    public init(fiveHour: UsageWindow?, sevenDay: UsageWindow?, reportedAt: Date = Date()) {
        self.fiveHour = fiveHour
        self.sevenDay = sevenDay
        self.reportedAt = reportedAt
    }

    public var isEmpty: Bool { fiveHour == nil && sevenDay == nil }

    /// A figure only means anything while sessions are still reporting it.
    /// Nothing writes a status line once the last one closes, so a number left
    /// on screen after that is describing a window that has since moved on.
    public static let freshness: TimeInterval = 15 * 60

    public func isFresh(now: Date = Date()) -> Bool {
        now.timeIntervalSince(reportedAt) < Self.freshness
    }

    /// Reads the `rate_limits` block of a status line payload.
    ///
    /// Everything is optional on purpose: the block is absent entirely on API
    /// billing, and a missing window has to read as "unknown" rather than as
    /// "none left".
    public static func read(statusLine payload: [String: Any], now: Date = Date()) -> Usage? {
        guard let limits = payload["rate_limits"] as? [String: Any] else { return nil }
        let usage = Usage(fiveHour: window(limits["five_hour"]),
                          sevenDay: window(limits["seven_day"]),
                          reportedAt: now)
        return usage.isEmpty ? nil : usage
    }

    static func window(_ raw: Any?) -> UsageWindow? {
        guard let raw = raw as? [String: Any],
              let percentage = raw["used_percentage"] as? Double else { return nil }
        return UsageWindow(used: percentage / 100, resetsAt: resetDate(raw["resets_at"]))
    }

    /// Seconds since the epoch in one build, an ISO 8601 string in another.
    /// Both are read, because guessing wrong here shows a countdown that is
    /// off by decades rather than one that is simply missing.
    static func resetDate(_ raw: Any?) -> Date? {
        if let seconds = raw as? Double, seconds > 0 {
            return Date(timeIntervalSince1970: seconds)
        }
        if let text = raw as? String {
            return TranscriptReader.parseTimestamp(text)
        }
        return nil
    }
}
