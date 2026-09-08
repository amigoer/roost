import Foundation
import Observation

/// One thing an agent's hook said about a session.
///
/// Claude Code writes a registry of its live sessions and a transcript for
/// each, so Roost reads those and asks it for nothing. Codex writes neither in
/// a form that says what is happening *now*, so a row for one is assembled out
/// of the events it is willing to announce.
public struct SessionReport: Codable, Sendable, Hashable {
    public let source: AgentKind
    public let sessionId: String
    public let cwd: String
    /// The hook event, verbatim, so the state machine below is the only place
    /// that has to know what any of them mean.
    public let event: String
    public let tool: String?
    public let detail: String?
    public let model: String?
    /// Processes above the hook, so a click has somewhere to climb. The hook
    /// itself is gone by then; the agent and its terminal are not.
    public let ancestors: [pid_t]
    public let at: Date

    public init(source: AgentKind, sessionId: String, cwd: String, event: String,
                tool: String? = nil, detail: String? = nil, model: String? = nil,
                ancestors: [pid_t] = [], at: Date = Date()) {
        self.source = source
        self.sessionId = sessionId
        self.cwd = cwd
        self.event = event
        self.tool = tool
        self.detail = detail
        self.model = model
        self.ancestors = ancestors
        self.at = at
    }
}

/// The sessions Roost knows about only because their hooks said so.
@MainActor
@Observable
public final class ReportedSessions {
    public init() {}

    /// A session whose hooks have said nothing this long is gone: an agent
    /// killed rather than closed sends no `SessionEnd`. Long enough that one
    /// left open overnight is still there in the morning.
    public static let forgetAfter: TimeInterval = 12 * 60 * 60

    struct Entry {
        var source: AgentKind
        var cwd: String
        var model: String?
        var startedAt: Date
        var event: String
        var eventAt: Date
        var tool: String?
        var detail: String?
        var ancestors: [pid_t]
    }

    private(set) var live: [String: Entry] = [:]

    public func receive(_ report: SessionReport) {
        guard !report.sessionId.isEmpty else { return }
        // A session that says it has ended is not one that is done; it is one
        // that is not there.
        guard report.event != "SessionEnd" else {
            live.removeValue(forKey: report.sessionId)
            return
        }

        var entry = live[report.sessionId] ?? Entry(
            source: report.source, cwd: report.cwd, model: report.model,
            startedAt: report.at, event: report.event, eventAt: report.at,
            tool: nil, detail: nil, ancestors: report.ancestors)

        entry.source = report.source
        entry.cwd = report.cwd
        entry.event = report.event
        entry.eventAt = report.at
        // Carried forward: not every event repeats what a session is running
        // on, and a row that blanks between two of them flickers.
        if let model = report.model { entry.model = model }
        if let tool = report.tool { entry.tool = tool }
        if let detail = report.detail { entry.detail = detail }
        if !report.ancestors.isEmpty { entry.ancestors = report.ancestors }
        // A turn that ends or begins says nothing about a tool, and neither
        // should the row.
        if report.event == "Stop" || report.event == "UserPromptSubmit" {
            entry.tool = nil
            entry.detail = nil
        }

        live[report.sessionId] = entry
    }

    /// Drops everything from one agent, for when it is told to stop talking.
    public func forget(_ agent: AgentKind) {
        live = live.filter { $0.value.source != agent }
    }

    public func expire(now: Date = Date()) {
        live = live.filter { now.timeIntervalSince($0.value.eventAt) < Self.forgetAfter }
    }

    /// A turn boundary a hook announced, for an agent whose sessions Roost can
    /// already see. The hook is the better clock and the transcript is the
    /// better record, so this carries only the clock.
    public struct TurnMark: Sendable, Hashable {
        public let event: String
        public let at: Date

        public init(event: String, at: Date) {
            self.event = event
            self.at = at
        }

        /// Only the two boundaries mean anything on their own. Everything else
        /// an agent announces is about a tool, which the transcript describes
        /// better than the payload does.
        var state: SessionState? {
            switch event {
            case "Stop": .done
            case "UserPromptSubmit": .running
            default: nil
            }
        }
    }

    public func turnMarks() -> [String: TurnMark] {
        live.reduce(into: [:]) { marks, entry in
            guard entry.value.source.hasRegistry else { return }
            marks[entry.key] = TurnMark(event: entry.value.event, at: entry.value.eventAt)
        }
    }

    /// What a hook adds to a session the scanner found on its own.
    ///
    /// Whichever spoke last wins. The transcript's timestamp advances with
    /// every tool call, so a `UserPromptSubmit` from the top of the turn goes
    /// stale within seconds and only the `Stop` at the end of it is ever newer
    /// than the file -- which is exactly the moment the file has nothing to say
    /// for another fifteen seconds.
    ///
    /// Nothing else about the row moves: the project, the title, the model and
    /// what the session was last seen doing all still come off disk.
    public static func sharpened(_ sessions: [Session],
                                 by marks: [String: TurnMark]) -> [Session] {
        guard !marks.isEmpty else { return sessions }
        return sessions.map { session in
            guard let mark = marks[session.id], mark.at > session.lastActivityAt,
                  let state = mark.state else { return session }
            var sharpened = session
            sharpened.state = state
            sharpened.lastActivityAt = mark.at
            if case .done = state {
                sharpened.activity = nil
                sharpened.detail = nil
            }
            sharpened.stateSince = mark.at
            return sharpened
        }
    }

    public func sessions(now: Date = Date()) -> [Session] {
        // Rows for agents nothing else can see. An agent with a registry is
        // found by reading it, and a second row for a session already listed is
        // worse than none: it would outlive the process by twelve hours.
        live.filter { !$0.value.source.hasRegistry }.map { id, entry in
            Session(id: id,
                    agent: entry.source,
                    pid: 0,
                    // No title anywhere in an agent's hook payload, so the row
                    // is named the way the id allows: enough of it to tell two
                    // sessions in one repo apart.
                    name: String(id.prefix(8)),
                    cwd: entry.cwd,
                    entrypoint: nil,
                    model: entry.model,
                    startedAt: entry.startedAt,
                    state: Self.state(of: entry, now: now),
                    stateSince: entry.eventAt,
                    activity: entry.tool,
                    detail: entry.detail,
                    lastActivityAt: entry.eventAt,
                    ancestors: entry.ancestors)
        }
    }

    /// What the last thing an agent said means now that some time has passed.
    static func state(of entry: Entry, now: Date) -> SessionState {
        switch entry.event {
        case "Stop":
            return .done
        case "PreToolUse":
            // A tool call with nothing after it is a slow build until the grace
            // period runs out, which is the same rule the transcripts get.
            guard now.timeIntervalSince(entry.eventAt) >= TranscriptReader.stallGrace else {
                return .running
            }
            return .blocked(.stalledTool(name: entry.tool ?? "tool"))
        default:
            return .running
        }
    }
}
