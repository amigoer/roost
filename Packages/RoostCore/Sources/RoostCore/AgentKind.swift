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

    /// Where this agent keeps its hooks.
    public var hooksURL: URL {
        let home = FileManager.default.homeDirectoryForCurrentUser
        switch self {
        case .claudeCode: return home.appending(path: ".claude/settings.json")
        case .codex: return home.appending(path: ".codex/hooks.json")
        }
    }

    /// The events that hold a session while the island answers.
    ///
    /// `PermissionRequest` runs where a permission prompt is about to appear
    /// and nowhere else, so it is the whole of the permission story: nothing
    /// has to be inferred about which calls would have been asked about.
    ///
    /// `PreToolUse` stays for the two calls that stop a session without being
    /// permissions at all -- a question and a plan -- because no permission
    /// event fires for either.
    public var answerEvents: [String] {
        switch self {
        case .claudeCode: ["PermissionRequest", "PreToolUse"]
        case .codex: ["PermissionRequest"]
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
