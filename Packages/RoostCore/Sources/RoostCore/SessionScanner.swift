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

    /// Titles live in a couple of hundred files that almost never change, so
    /// re-reading them on every scan was measurable CPU for nothing.
    private static let titleRefreshInterval: TimeInterval = 30

    private var titles: [String: String] = [:]
    private var titlesReadAt: Date = .distantPast
    private var transcriptCache: [String: Cached] = [:]
    private var stateSince: [String: Date] = [:]
    private var lastStates: [String: SessionState] = [:]

    public init() {}

    public func scan(now: Date = Date()) -> [Session] {
        let entries = SessionRegistry.liveEntries()
        refreshTitlesIfStale(now: now)
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

            sessions.append(Session(
                id: entry.sessionId,
                pid: entry.pid,
                name: titles[entry.sessionId]
                    ?? entry.name
                    ?? URL(fileURLWithPath: entry.cwd).lastPathComponent,
                cwd: entry.cwd,
                entrypoint: entry.entrypoint,
                startedAt: entry.startedAt,
                state: state,
                stateSince: stateSince[entry.sessionId] ?? now,
                activity: reading?.activity,
                lastActivityAt: reading?.lastActivityAt ?? entry.startedAt
            ))
        }

        transcriptCache = transcriptCache.filter { live.contains($0.key) }
        stateSince = stateSince.filter { live.contains($0.key) }
        lastStates = lastStates.filter { live.contains($0.key) }

        return sessions.sorted { lhs, rhs in
            if lhs.state.signalLevel != rhs.state.signalLevel {
                return lhs.state.signalLevel > rhs.state.signalLevel
            }
            return lhs.startedAt > rhs.startedAt
        }
    }

    private func refreshTitlesIfStale(now: Date) {
        guard now.timeIntervalSince(titlesReadAt) >= Self.titleRefreshInterval else { return }
        titles = DesktopTitles.byCLISessionId()
        titlesReadAt = now
    }

    /// Parses only when the transcript actually changed. State is still
    /// re-derived every tick from the cached facts, so a pending tool crossing
    /// the grace line is noticed without re-reading anything.
    private func reading(for sessionId: String, now: Date) -> TranscriptReader.Reading? {
        guard let url = TranscriptReader.transcriptURL(sessionId: sessionId) else { return nil }
        let modifiedAt = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?
            .contentModificationDate ?? .distantPast

        if let cached = transcriptCache[sessionId], cached.modifiedAt == modifiedAt {
            return TranscriptReader.state(from: cached.facts, now: now)
        }

        guard let facts = TranscriptReader.facts(url: url) else { return nil }
        transcriptCache[sessionId] = Cached(modifiedAt: modifiedAt, facts: facts)
        return TranscriptReader.state(from: facts, now: now)
    }
}
