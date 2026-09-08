import Foundation

/// One quota window.
public struct UsageWindow: Codable, Sendable, Hashable {
    /// How much of the window is spent, 0-1.
    public let used: Double
    /// When it empties again, when the payload says.
    public let resetsAt: Date?
    /// Why the window will not serve, when the server says so. Only the reading
    /// that comes from Anthropic carries it; a status line never does.
    public let lockedReason: String?

    public init(used: Double, resetsAt: Date? = nil, lockedReason: String? = nil) {
        self.used = min(max(used, 0), 1)
        self.resetsAt = resetsAt
        self.lockedReason = lockedReason
    }

    /// A helper from an older bundle sends the two fields it knew about, and
    /// one already running has a session behind it.
    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        self.init(used: try values.decode(Double.self, forKey: .used),
                  resetsAt: try values.decodeIfPresent(Date.self, forKey: .resetsAt),
                  lockedReason: try values.decodeIfPresent(String.self, forKey: .lockedReason))
    }

    public func remaining(now: Date = Date()) -> TimeInterval? {
        guard let resetsAt else { return nil }
        return max(0, resetsAt.timeIntervalSince(now))
    }

    /// Nothing more will run on this window until it comes back. Said by the
    /// server where it can be, and inferred from a full window where it cannot:
    /// a status line reports the figure and never the lock.
    public var isSpent: Bool { lockedReason != nil || used >= 1 }
}

/// A window covering only part of the account's traffic -- one model, today.
///
/// Carried as a label rather than as an enumeration: the server decides what it
/// scopes, and a scope nobody here has heard of has to be able to arrive as a
/// name instead of being dropped as an unknown case.
public struct ScopedWindow: Codable, Sendable, Hashable {
    public let label: String
    public let window: UsageWindow

    public init(label: String, window: UsageWindow) {
        self.label = label
        self.window = window
    }
}

/// What is left of the account's quota.
///
/// Account-wide rather than per session: every session on this Mac spends the
/// same five-hour window, so the island reports it once for the whole fleet.
public struct Usage: Codable, Sendable, Hashable {
    /// Which of the two paths a reading came down, so two readings of the same
    /// window can be told apart by more than their age when one has to win.
    public enum Source: String, Codable, Sendable {
        /// Wrapped status line: local, and only while a session renders one.
        case statusLine
        /// Asked of Anthropic directly: current whether or not anything is running.
        case api
    }

    public let fiveHour: UsageWindow?
    public let sevenDay: UsageWindow?
    /// Per-model weeklies. Detail rather than headline: they explain a seven-day
    /// figure, and there is no room in a footer to explain anything.
    public let scoped: [ScopedWindow]
    public let source: Source
    public let reportedAt: Date

    public init(fiveHour: UsageWindow?, sevenDay: UsageWindow?,
                scoped: [ScopedWindow] = [], source: Source = .statusLine,
                reportedAt: Date = Date()) {
        self.fiveHour = fiveHour
        self.sevenDay = sevenDay
        self.scoped = scoped
        self.source = source
        self.reportedAt = reportedAt
    }

    /// Defaults for everything a helper from an older bundle does not send.
    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        self.init(fiveHour: try values.decodeIfPresent(UsageWindow.self, forKey: .fiveHour),
                  sevenDay: try values.decodeIfPresent(UsageWindow.self, forKey: .sevenDay),
                  scoped: try values.decodeIfPresent([ScopedWindow].self, forKey: .scoped) ?? [],
                  source: try values.decodeIfPresent(Source.self, forKey: .source) ?? .statusLine,
                  reportedAt: try values.decode(Date.self, forKey: .reportedAt))
    }

    public var isEmpty: Bool { fiveHour == nil && sevenDay == nil }

    /// A window has run out and nothing will run on it until it returns.
    public var isSpent: Bool { spent != nil }

    /// The spent window itself, five-hour first: it is the one that comes back
    /// within the day, so it is the one worth counting down to.
    public var spent: UsageWindow? {
        [fiveHour, sevenDay].compactMap { $0 }.first(where: \.isSpent)
    }

    /// The window nearest to full, which is the one that decides when work
    /// stops. What the island escalates on, and what it names when it does.
    public var binding: (label: WindowLabel, window: UsageWindow)? {
        let candidates: [(WindowLabel, UsageWindow)] =
            [(.fiveHour, fiveHour), (.sevenDay, sevenDay)].compactMap { label, window in
                window.map { (label, $0) }
            }
        return candidates.max { $0.1.used < $1.1.used }
    }

    public enum WindowLabel: String, Sendable { case fiveHour, sevenDay }

    /// A figure only describes the present for so long. Nothing writes a status
    /// line once the last session closes, and a poll can fail for an hour.
    ///
    /// Past this the reading is shown with the time it was taken rather than
    /// hidden: someone opening the island to ask how much is left is worse
    /// served by nothing at all than by a number and its age.
    public static let freshness: TimeInterval = 15 * 60

    public func isFresh(now: Date = Date()) -> Bool {
        now.timeIntervalSince(reportedAt) < Self.freshness
    }

    /// Whether the window has turned over since this was taken, which is the
    /// one thing a stale reading can still be sure of. What has been spent
    /// since is unknown, so the figure is dropped rather than shown as zero.
    public func hasReset(_ window: UsageWindow?, now: Date = Date()) -> Bool {
        guard let resetsAt = window?.resetsAt else { return false }
        return resetsAt <= now
    }

    /// The newer reading wins, window by window where it can.
    ///
    /// Both paths report every window they know about at once, so the borrow
    /// below only happens when a source genuinely stopped carrying one -- rare
    /// enough that giving the borrowed window the winner's timestamp is closer
    /// to true than dropping it.
    public func merged(with other: Usage?) -> Usage {
        guard let other else { return self }
        let (new, old) = reportedAt >= other.reportedAt ? (self, other) : (other, self)
        return Usage(fiveHour: new.fiveHour ?? old.fiveHour,
                     sevenDay: new.sevenDay ?? old.sevenDay,
                     scoped: new.scoped.isEmpty ? old.scoped : new.scoped,
                     source: new.source,
                     reportedAt: new.reportedAt)
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
                          source: .statusLine,
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
