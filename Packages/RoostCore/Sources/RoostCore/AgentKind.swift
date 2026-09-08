import Foundation

/// Which tool a session belongs to.
///
/// Kept out of the view layer because it decides more than a mark: which
/// registry a session came from, which settings file its hooks live in, and
/// what shape a decision has to be in on the way back.
public enum AgentKind: String, Codable, Sendable, Hashable, CaseIterable {
    case claudeCode
    case codex

    /// Names as their own tools write them, in either language: a product
    /// name is not something to translate.
    public var label: String {
        switch self {
        case .claudeCode: "Claude Code"
        case .codex: "Codex"
        }
    }

    /// Whether this agent's hook fires only where a prompt would really have
    /// appeared.
    ///
    /// Claude Code's `PreToolUse` fires for every call, so Roost has to read
    /// the session's permission mode to work out which of them would have been
    /// asked about. Codex has a `PermissionRequest` event that *is* the prompt,
    /// which is both exact and cheaper.
    public var promptsAreExact: Bool {
        switch self {
        case .claudeCode: false
        case .codex: true
        }
    }

    /// Where this agent keeps its hooks.
    public var hooksURL: URL {
        let home = FileManager.default.homeDirectoryForCurrentUser
        switch self {
        case .claudeCode: return home.appending(path: ".claude/settings.json")
        case .codex: return home.appending(path: ".codex/hooks.json")
        }
    }

    /// The event that waits on an answer.
    public var permissionEvent: String {
        switch self {
        case .claudeCode: "PreToolUse"
        case .codex: "PermissionRequest"
        }
    }

    /// Events that are reported and never waited on.
    ///
    /// Claude Code writes a registry of its live sessions and a transcript for
    /// each, so Roost reads them and asks it for nothing. Codex writes neither
    /// in a form that says what is happening now, so a row for one is built
    /// out of these instead.
    public var lifecycleEvents: [String] {
        switch self {
        case .claudeCode: []
        case .codex: ["SessionStart", "UserPromptSubmit", "PreToolUse",
                      "PostToolUse", "Stop", "SessionEnd"]
        }
    }
}
