import Foundation

/// Derives live state by tailing a session transcript.
///
/// This is the fallback path: Claude Code writes nothing at the moment a
/// permission prompt appears, so a dangling tool call plus elapsed time is the
/// only evidence available without hooks installed.
public enum TranscriptReader {
    /// A dangling Bash may just be a slow build, so ordinary tools need a wait
    /// before they count as blocked. Tools that only a human can answer do not.
    public static let stallGrace: TimeInterval = 45

    /// Tool calls that are, by definition, waiting on a person.
    static let humanOnlyTools: Set<String> = ["AskUserQuestion", "ExitPlanMode"]

    /// Enough to cover the recent exchange. Only the last semantic line and any
    /// dangling tool call matter here, so the whole conversation is never needed.
    static let tailBytes: UInt64 = 262_144

    public static func transcriptURL(sessionId: String,
                                     projectsRoot: URL? = nil) -> URL? {
        let root = projectsRoot
            ?? FileManager.default.homeDirectoryForCurrentUser.appending(path: ".claude/projects")
        // Glob by session id: the directory name encodes the cwd lossily
        // (both "/" and "." collapse to "-"), so it cannot be reconstructed.
        guard let dirs = try? FileManager.default.contentsOfDirectory(
            at: root, includingPropertiesForKeys: nil) else { return nil }
        for dir in dirs {
            let candidate = dir.appending(path: "\(sessionId).jsonl")
            if FileManager.default.fileExists(atPath: candidate.path) { return candidate }
        }
        return nil
    }

    /// What parsing the file yields. Separated from `Reading` so state can be
    /// re-derived as time passes without touching the disk again: a pending tool
    /// crosses the grace line with nothing being written, and re-reading every
    /// transcript on a timer to notice that was the app's largest cost.
    public struct Facts: Sendable {
        public var pendingTool: String?
        public var pendingDetail: String?
        public var pendingSince: Date?
        public var lastStopReason: String?
        public var lastToolName: String?
        public var lastDetail: String?
        public var lastActivityAt: Date
        /// How the session answers permission prompts, as of its last turn or
        /// of the last switch made during one. The only record a session
        /// started in a terminal leaves anywhere.
        public var permissionMode: String?
    }

    public struct Reading: Sendable {
        public var state: SessionState
        public var activity: String?
        /// What that tool is working on: the command, the file, the pattern.
        public var detail: String?
        public var lastActivityAt: Date
        /// When the agent actually stopped, taken from the dangling tool call's
        /// own timestamp. Without this the elapsed time would start counting
        /// from whenever the grace period happened to elapse, which understates
        /// a long wait by exactly the length of the grace period.
        public var waitingSince: Date?
    }

    public static func read(url: URL, now: Date = Date()) -> Reading? {
        guard let facts = facts(url: url) else { return nil }
        return state(from: facts, now: now)
    }

    /// Pure: no IO, safe to call every refresh tick.
    public static func state(from facts: Facts, now: Date) -> Reading {
        if let tool = facts.pendingTool {
            let since = facts.pendingSince ?? facts.lastActivityAt
            if humanOnlyTools.contains(tool) {
                let reason: BlockReason = tool == "AskUserQuestion" ? .question : .planApproval
                return Reading(state: .blocked(reason), activity: tool, detail: facts.pendingDetail,
                               lastActivityAt: facts.lastActivityAt, waitingSince: since)
            }
            if now.timeIntervalSince(since) >= stallGrace {
                return Reading(state: .blocked(.stalledTool(name: tool)), activity: tool,
                               detail: facts.pendingDetail,
                               lastActivityAt: facts.lastActivityAt, waitingSince: since)
            }
            return Reading(state: .running, activity: tool, detail: facts.pendingDetail,
                           lastActivityAt: facts.lastActivityAt, waitingSince: nil)
        }

        if facts.lastStopReason == "end_turn" {
            return Reading(state: .done, activity: nil, detail: nil,
                           lastActivityAt: facts.lastActivityAt, waitingSince: nil)
        }
        return Reading(state: .running, activity: facts.lastToolName, detail: facts.lastDetail,
                       lastActivityAt: facts.lastActivityAt, waitingSince: nil)
    }

    public static func facts(url: URL) -> Facts? {
        guard let lines = tailLines(of: url) else { return nil }

        var toolUses: [String: (name: String, at: Date?, detail: String?)] = [:]
        var toolResults = Set<String>()
        var lastSemanticStop: String?
        var lastSemanticAt: Date?
        var lastToolName: String?
        var lastDetail: String?
        var permissionMode: String?

        for line in lines {
            guard let data = line.data(using: .utf8),
                  let record = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let type = record["type"] as? String
            else { continue }

            // Carried by each turn, and written on its own line the moment
            // somebody changes it mid-turn, so the last one seen is current.
            if let mode = record["permissionMode"] as? String { permissionMode = mode }

            // Metadata lines (last-prompt, mode, ai-title, ...) are appended
            // after the semantic ones and mean nothing, so only these two count.
            guard type == "assistant" || type == "user" else { continue }

            let timestamp = (record["timestamp"] as? String).flatMap(Self.parseTimestamp)
            if let timestamp { lastSemanticAt = timestamp }

            guard let message = record["message"] as? [String: Any] else { continue }
            if let stop = message["stop_reason"] as? String { lastSemanticStop = stop }

            for block in (message["content"] as? [[String: Any]]) ?? [] {
                switch block["type"] as? String {
                case "tool_use":
                    if let id = block["id"] as? String {
                        let name = (block["name"] as? String) ?? "tool"
                        let detail = Self.detail(from: block["input"] as? [String: Any])
                        toolUses[id] = (name, timestamp, detail)
                        lastToolName = name
                        lastDetail = detail
                    }
                case "tool_result":
                    if let id = block["tool_use_id"] as? String { toolResults.insert(id) }
                default:
                    break
                }
            }
        }

        let modified = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?
            .contentModificationDate
        let lastActivity = lastSemanticAt ?? modified ?? Date()
        let dangling = toolUses.first { !toolResults.contains($0.key) }

        return Facts(pendingTool: dangling?.value.name,
                     pendingDetail: dangling?.value.detail,
                     pendingSince: dangling?.value.at,
                     lastStopReason: lastSemanticStop,
                     lastToolName: lastToolName,
                     lastDetail: lastDetail,
                     lastActivityAt: lastActivity,
                     permissionMode: permissionMode)
    }

    /// Arguments worth showing, in the order a person would want them. Keyed by
    /// argument rather than by tool name so MCP and plugin tools, whose names
    /// nobody can enumerate, still say something useful.
    static let detailKeys = ["command", "file_path", "pattern", "query", "url",
                             "description", "path", "skill", "prompt"]

    /// A one-line hint of what a tool call is actually doing. Without it every
    /// busy session reads "running Bash", which says nothing about which one to
    /// go look at.
    static func detail(from input: [String: Any]?) -> String? {
        guard let input else { return nil }
        for key in detailKeys {
            guard let raw = input[key] as? String else { continue }
            let isPath = key == "file_path" || key == "path"
            return condensed(isPath ? URL(fileURLWithPath: raw).lastPathComponent : raw)
        }
        return nil
    }

    /// First line only, cut to what a row can hold.
    static func condensed(_ value: String, limit: Int = 44) -> String? {
        let line = value.split(whereSeparator: \.isNewline).first?
            .trimmingCharacters(in: .whitespaces) ?? ""
        guard !line.isEmpty else { return nil }
        return line.count <= limit ? line : line.prefix(limit - 1) + "…"
    }

    // Value-type format styles, unlike ISO8601DateFormatter, are Sendable.
    static let fractionalISO = Date.ISO8601FormatStyle(includingFractionalSeconds: true)
    static let plainISO = Date.ISO8601FormatStyle()

    static func parseTimestamp(_ value: String) -> Date? {
        (try? Date(value, strategy: fractionalISO)) ?? (try? Date(value, strategy: plainISO))
    }

    static func tailLines(of url: URL) -> [String]? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        guard let size = try? handle.seekToEnd() else { return nil }
        let start = size > tailBytes ? size - tailBytes : 0
        try? handle.seek(toOffset: start)
        guard let data = try? handle.readToEnd(),
              let text = String(data: data, encoding: .utf8) else { return nil }
        var lines = text.split(separator: "\n", omittingEmptySubsequences: true).map(String.init)
        // The first line is probably cut in half by the tail offset.
        if start > 0, !lines.isEmpty { lines.removeFirst() }
        return lines
    }
}
