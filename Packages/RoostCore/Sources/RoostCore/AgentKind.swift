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
}
