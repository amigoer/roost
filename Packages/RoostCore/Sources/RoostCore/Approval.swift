import Foundation

/// A tool call held at the gate, waiting for a person to say yes or no.
public struct ApprovalRequest: Codable, Sendable, Identifiable, Hashable {
    public let id: String
    /// CLI session id, so the request can be matched to a row.
    public let sessionId: String
    public let cwd: String
    public let tool: String
    /// The argument worth reading before deciding: the command, the file, the url.
    public let detail: String?
    /// The sub-agent the call came from, by type name, when it did not come
    /// from the session's main thread.
    public let agent: String?
    public let receivedAt: Date

    public var projectName: String { URL(fileURLWithPath: cwd).lastPathComponent }

    /// Why the session behind this call cannot move. Which of the two it is
    /// depends on who made the call, because "Explore needs input" and "needs
    /// permission: Bash" send you to different places in the conversation.
    public var blockReason: BlockReason {
        if let agent { return .agentNeedsInput(label: agent) }
        return .permissionPrompt(tool: tool)
    }

    public init(id: String = UUID().uuidString, sessionId: String, cwd: String,
                tool: String, detail: String?, agent: String? = nil,
                receivedAt: Date = Date()) {
        self.id = id
        self.sessionId = sessionId
        self.cwd = cwd
        self.tool = tool
        self.detail = detail
        self.agent = agent
        self.receivedAt = receivedAt
    }
}

extension Session {
    /// This session with the call it has waiting at the gate.
    ///
    /// Claude Code writes nothing at the moment a prompt appears, so the
    /// transcript still reads as a tool in flight. Without this the row says
    /// "running Bash" while a card above it asks whether that Bash may run,
    /// and the fleet headline counts the session as running rather than
    /// waiting -- which is the one thing the island exists to say.
    public func held(by request: ApprovalRequest) -> Session {
        var session = self
        session.state = .blocked(request.blockReason)
        session.stateSince = request.receivedAt
        session.detail = request.detail
        return session
    }
}

public enum ApprovalDecision: String, Codable, Sendable {
    case allow
    case deny
    /// Hand it back: the session prompts the way it always did.
    case ask
}

public struct ApprovalReply: Codable, Sendable {
    public let decision: ApprovalDecision
    public let reason: String?

    public init(decision: ApprovalDecision, reason: String? = nil) {
        self.decision = decision
        self.reason = reason
    }
}

/// Which tool calls are worth holding.
///
/// Getting this wrong in the loud direction is worse than getting it wrong in
/// the quiet one: a card for a tool that would never have prompted is pure
/// interruption, while a missed one just prompts where it always did.
public enum ApprovalGate {
    /// Tools that never raise a permission prompt, filtered in the hook itself
    /// so the common path never pays for a round trip.
    public static let silent: Set<String> = [
        "Read", "Glob", "Grep", "NotebookRead", "TodoWrite", "BashOutput", "KillShell",
        "AskUserQuestion", "ExitPlanMode", "SlashCommand", "ListMcpResources",
    ]

    /// Tools whose prompt an accept-edits session has already answered once.
    public static let edits: Set<String> = ["Write", "Edit", "MultiEdit", "NotebookEdit"]

    /// Cheap filter, applied by the hook with nothing but the tool name.
    public static func mayPrompt(tool: String) -> Bool { !silent.contains(tool) }

    /// The real policy, applied by the app, which knows the session's mode.
    ///
    /// Only the modes that still raise a prompt are held. `nil` is a session
    /// with no record of its own -- one started in a terminal, which prompts
    /// unless it was told not to. Every mode the desktop app has shipped apart
    /// from `default` loosens permissions rather than tightening them, so a
    /// name this does not recognise is let through with the rest: a card for a
    /// call the session would have run anyway is not a safety net, and from
    /// the outside it is indistinguishable from a prompt that was real.
    public static func shouldAsk(tool: String, permissionMode: String?) -> Bool {
        guard mayPrompt(tool: tool) else { return false }
        switch permissionMode {
        case nil, "default": return true
        case "acceptEdits": return !edits.contains(tool)
        // "auto", "bypassPermissions", "plan", and whatever comes next.
        default: return false
        }
    }

    /// The argument a person needs to decide, by the same rules the rows use.
    public static func detail(tool: String, input: [String: Any]?) -> String? {
        TranscriptReader.detail(from: input)
    }
}

/// Where the app listens and the hook connects.
///
/// Kept short and under the user's own directory: `sun_path` runs out at 104
/// bytes, and the socket must not be readable by other accounts.
public enum ApprovalSocket {
    public static func directory() -> URL {
        URL(fileURLWithPath: "/tmp/roost-\(getuid())")
    }

    public static func path() -> String {
        directory().appending(path: "approvals.sock").path
    }

    /// Long enough that someone away from the keyboard can still answer, short
    /// enough that an unanswered card gives the session back to its own prompt.
    public static let timeout: TimeInterval = 60
}
