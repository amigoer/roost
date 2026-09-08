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

    /// The same path as a person would write it down, for a message that has
    /// to be actionable.
    public var hooksPath: String {
        (hooksURL.path as NSString).abbreviatingWithTildeInPath
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
    /// Codex writes no registry and no transcript that says what is happening
    /// now, so a row for one is built entirely out of these.
    ///
    /// Claude Code writes both, and they answer *what* a session is doing far
    /// better than any hook payload could -- but they answer *when* badly. A
    /// turn's last message is not written until the model has finished writing
    /// it, measured here at a median of 15 seconds after the work stopped, and
    /// the row reads as busy for all of it while the answer is already on
    /// screen. These two say the same thing at the moment it becomes true, and
    /// nothing else about the row changes.
    public var lifecycleEvents: [String] {
        switch self {
        case .claudeCode: ["UserPromptSubmit", "Stop"]
        case .codex: ["SessionStart", "UserPromptSubmit", "PreToolUse",
                      "PostToolUse", "Stop", "SessionEnd"]
        }
    }

    /// Whether Roost can find this agent's live sessions without being told.
    ///
    /// Claude Code writes a registry of them, so its hooks only ever sharpen a
    /// row that already exists. Codex writes none, so a row for one of its
    /// sessions exists exactly as long as its hooks keep saying so.
    public var hasRegistry: Bool { self == .claudeCode }
}
