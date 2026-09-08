import Foundation

/// Joins the process registry to transcript state.
///
/// An actor so the file IO stays off the main thread and the caches below are
/// safe to mutate from whichever task drives the refresh.
public actor SessionScanner {
    private struct Cached {
        var modifiedAt: Date
        var facts: TranscriptReader.Facts
    }

    /// The desktop store is a couple of hundred files that almost never
    /// change, so re-reading them on every scan was measurable CPU for nothing.
    private static let desktopRefreshInterval: TimeInterval = 30

    /// Deciding whether to hold a tool call is worth paying that read for: a
    /// conversation started since the last one is not in it at all, and a mode
    /// switched a moment ago is the difference between a card that belongs on
    /// screen and one that interrupts for nothing.
    private static let desktopDecisionAge: TimeInterval = 2

    private var desktop: [String: DesktopSession] = [:]
    private var desktopReadAt: Date = .distantPast
    private var transcriptCache: [String: Cached] = [:]
    private var stateSince: [String: Date] = [:]
    private var lastStates: [String: SessionState] = [:]

    public init() {}

    public func scan(now: Date = Date()) -> [Session] {
        let entries = SessionRegistry.deduplicated(SessionRegistry.liveEntries())
        refreshDesktop(now: now, olderThan: Self.desktopRefreshInterval)
        var live = Set<String>()
        var sessions: [Session] = []

        for entry in entries {
            live.insert(entry.sessionId)
            let reading = reading(for: entry.sessionId, now: now)
            let state = reading?.state ?? .running

            if lastStates[entry.sessionId] != state {
                lastStates[entry.sessionId] = state
                stateSince[entry.sessionId] = reading?.waitingSince ?? now
            }

            let known = desktop[entry.sessionId]
            sessions.append(Session(
                id: entry.sessionId,
                pid: entry.pid,
                name: known?.title
                    ?? entry.name
                    ?? URL(fileURLWithPath: entry.cwd).lastPathComponent,
                cwd: entry.cwd,
                entrypoint: entry.entrypoint,
                model: known?.modelLabel,
                startedAt: entry.startedAt,
                state: state,
                stateSince: stateSince[entry.sessionId] ?? now,
                activity: reading?.activity,
                detail: reading?.detail,
                lastActivityAt: reading?.lastActivityAt ?? entry.startedAt
            ))
        }

        transcriptCache = transcriptCache.filter { live.contains($0.key) }
        stateSince = stateSince.filter { live.contains($0.key) }
        lastStates = lastStates.filter { live.contains($0.key) }

        return Session.ordered(sessions)
    }

    /// How a session answers permission prompts, asked at the moment a tool
    /// call is about to be held.
    ///
    /// The transcript comes first: it carries the mode of the last turn and of
    /// any switch made during one, and it is the only record a session started
    /// in a terminal leaves at all. The desktop store answers for the rest --
    /// a session whose last turn has scrolled out of the tail, or one opened
    /// since the last read of it.
    public func permissionMode(for sessionId: String, now: Date = Date()) -> String? {
        if let mode = facts(for: sessionId)?.permissionMode { return mode }
        refreshDesktop(now: now, olderThan: Self.desktopDecisionAge)
        return desktop[sessionId]?.permissionMode
    }

    private func refreshDesktop(now: Date, olderThan age: TimeInterval) {
        guard now.timeIntervalSince(desktopReadAt) >= age else { return }
        desktop = DesktopSessions.byCLISessionId()
        desktopReadAt = now
    }

    /// State is re-derived every tick from the cached facts, so a pending tool
    /// crossing the grace line is noticed without re-reading anything.
    private func reading(for sessionId: String, now: Date) -> TranscriptReader.Reading? {
        guard let facts = facts(for: sessionId) else { return nil }
        return TranscriptReader.state(from: facts, now: now)
    }

    /// Parses only when the transcript actually changed.
    private func facts(for sessionId: String) -> TranscriptReader.Facts? {
        guard let url = TranscriptReader.transcriptURL(sessionId: sessionId) else { return nil }
        let modifiedAt = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?
            .contentModificationDate ?? .distantPast

        if let cached = transcriptCache[sessionId], cached.modifiedAt == modifiedAt {
            return cached.facts
        }

        guard let facts = TranscriptReader.facts(url: url) else { return nil }
        transcriptCache[sessionId] = Cached(modifiedAt: modifiedAt, facts: facts)
        return facts
    }
}
