import Foundation

/// Why a session cannot make progress without the user.
public enum BlockReason: Sendable, Hashable {
    /// A tool call of this session's is held at the gate, waiting for Deny or
    /// Allow. Known only to the app doing the holding: Claude Code writes
    /// nothing at the moment it prompts.
    case permissionPrompt(tool: String?)
    /// A dangling AskUserQuestion: by definition waiting on a human.
    case question
    /// A dangling ExitPlanMode: waiting for plan approval.
    case planApproval
    /// The held call came from a named sub-agent rather than from the
    /// session's main thread, so the row names the agent instead of the tool.
    case agentNeedsInput(label: String?)
    /// A tool call has been outstanding past the grace period.
    case stalledTool(name: String)

    /// Reasons that are unambiguous the instant they are observed, with no
    /// grace period: nothing but a human can resolve them.
    public var isImmediate: Bool {
        switch self {
        case .question, .planApproval, .permissionPrompt, .agentNeedsInput: true
        case .stalledTool: false
        }
    }
}

public enum SessionState: Sendable, Hashable {
    /// Turn ended; the session wants a reply but nothing is burning.
    case done
    /// Actively producing output or running a tool.
    case running
    /// Stopped, and only the user can unstick it. The state Roost exists for.
    case blocked(BlockReason)
}

/// What the collapsed strip renders. Ordered by how much it demands attention.
///
/// `done` sits *below* `running` deliberately: a finished session is the
/// quietest thing on screen, while an in-flight one at least implies motion.
/// Only `blocked` is allowed to be loud.
public enum SignalLevel: Int, Sendable, Hashable, Comparable, CaseIterable {
    case dormant = 0
    case done = 1
    case running = 2
    case blocked = 3

    public static func < (lhs: Self, rhs: Self) -> Bool { lhs.rawValue < rhs.rawValue }
}

extension SessionState {
    public var signalLevel: SignalLevel {
        switch self {
        case .done: .done
        case .running: .running
        case .blocked: .blocked
        }
    }
}

extension SignalLevel {
    /// The collapsed strip shows one state for all sessions: the loudest one.
    public static func aggregate(_ states: some Sequence<SessionState>) -> SignalLevel {
        states.reduce(into: SignalLevel.dormant) { result, state in
            result = max(result, state.signalLevel)
        }
    }
}
