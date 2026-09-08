import Foundation

public struct Session: Sendable, Identifiable, Hashable {
    public let id: String
    public let pid: pid_t
    /// Human-readable name the CLI derives, e.g. "perch-9b".
    public let name: String
    public let cwd: String
    public let entrypoint: String?
    /// Model the session is running, short form.
    public let model: String?
    public let startedAt: Date
    public var state: SessionState
    /// When the session entered its current state, for escalation timing.
    public var stateSince: Date
    /// Short hint about what it is doing, e.g. a tool name.
    public var activity: String?
    /// What that tool is working on: the command, the file, the pattern.
    public var detail: String?
    /// Last semantic line in the transcript. A `done` session is not a finished
    /// one: the process stays alive, so this is what separates a conversation
    /// you just replied in from one you abandoned days ago.
    public var lastActivityAt: Date

    /// Idle long enough that it is clutter rather than context.
    public func isStale(now: Date = Date(), threshold: TimeInterval = 1800) -> Bool {
        guard case .done = state else { return false }
        return now.timeIntervalSince(lastActivityAt) > threshold
    }

    public var projectName: String {
        URL(fileURLWithPath: cwd).lastPathComponent
    }

    /// The order rows are listed in: loudest first, then newest. Shared, so a
    /// session the app itself knows is blocked sorts with the rest.
    public static func ordered(_ sessions: [Session]) -> [Session] {
        sessions.sorted { lhs, rhs in
            if lhs.state.signalLevel != rhs.state.signalLevel {
                return lhs.state.signalLevel > rhs.state.signalLevel
            }
            return lhs.startedAt > rhs.startedAt
        }
    }

    public var blockedFor: TimeInterval {
        guard case .blocked = state else { return 0 }
        return Date().timeIntervalSince(stateSince)
    }

    public init(id: String, pid: pid_t, name: String, cwd: String, entrypoint: String?,
                model: String? = nil,
                startedAt: Date, state: SessionState, stateSince: Date,
                activity: String?, detail: String? = nil, lastActivityAt: Date) {
        self.id = id
        self.pid = pid
        self.name = name
        self.cwd = cwd
        self.entrypoint = entrypoint
        self.model = model
        self.startedAt = startedAt
        self.state = state
        self.stateSince = stateSince
        self.activity = activity
        self.detail = detail
        self.lastActivityAt = lastActivityAt
    }
}
