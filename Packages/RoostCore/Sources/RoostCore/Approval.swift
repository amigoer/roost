import Foundation

/// What a held call is asking for, and everything the island needs to answer it.
///
/// Three shapes, because three different things stop a session: a tool that
/// needs permission, a question that needs an answer, and a plan that needs a
/// verdict. They come down the same wire and land on the same card.
public enum HeldKind: Codable, Sendable, Hashable {
    /// A tool call waiting for Deny or Allow.
    case permission
    /// An `AskUserQuestion`, with the options as the session offered them.
    case question(HeldQuestion)
    /// An `ExitPlanMode`, carrying the plan it wants to start working from.
    case plan(String)
}

/// A question a session asked, in the shape the island can answer it.
public struct HeldQuestion: Codable, Sendable, Hashable {
    public struct Option: Codable, Sendable, Hashable {
        public let label: String
        /// What choosing it means, shown after the label where there is room.
        public let description: String?

        public init(label: String, description: String? = nil) {
            self.label = label
            self.description = description
        }
    }

    /// What was asked, in the session's own words.
    public let prompt: String
    /// The chip Claude Code puts above the question, e.g. "Auth method".
    public let header: String?
    public let options: [Option]

    public init(prompt: String, header: String? = nil, options: [Option]) {
        self.prompt = prompt
        self.header = header
        self.options = options
    }
}

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

    /// Which tool is asking. Absent from a payload written by an older hook,
    /// which only ever spoke for Claude Code.
    private let heldSource: AgentKind?
    public var source: AgentKind { heldSource ?? .claudeCode }

    /// What answering this actually means.
    ///
    /// Stored optional because a bundle can be left holding an older
    /// `roost-hook`, whose payloads predate the field and only ever meant a
    /// permission. Approvals must not stop working over a missing key.
    private let heldKind: HeldKind?
    public var kind: HeldKind { heldKind ?? .permission }

    enum CodingKeys: String, CodingKey {
        case id, sessionId, cwd, tool, detail, agent, receivedAt
        case heldKind = "kind"
        case heldSource = "source"
    }

    public var projectName: String { URL(fileURLWithPath: cwd).lastPathComponent }

    /// Why the session behind this call cannot move. Which of them it is
    /// decides where the row sends you: "Explore needs input", "asked you a
    /// question" and "needs permission: Bash" are three different places in
    /// the conversation.
    public var blockReason: BlockReason {
        if case .question = kind { return .question }
        if case .plan = kind { return .planApproval }
        if let agent { return .agentNeedsInput(label: agent) }
        return .permissionPrompt(tool: tool)
    }

    public init(id: String = UUID().uuidString, sessionId: String, cwd: String,
                tool: String, detail: String?, agent: String? = nil,
                receivedAt: Date = Date(), kind: HeldKind = .permission,
                source: AgentKind = .claudeCode) {
        self.id = id
        self.sessionId = sessionId
        self.cwd = cwd
        self.tool = tool
        self.detail = detail
        self.agent = agent
        self.receivedAt = receivedAt
        self.heldKind = kind
        self.heldSource = source
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

    /// Answering a question is a denial on the wire.
    ///
    /// There is no hook decision that means "here is the answer": blocking the
    /// call and handing back a reason is the only way to put words in front of
    /// the model, and the reason is exactly what it reads next.
    public static func answer(_ chosen: String) -> ApprovalReply {
        ApprovalReply(decision: .deny, reason: "The user answered from Roost: \(chosen)")
    }

    /// Approving a plan is letting `ExitPlanMode` run: the prompt it would have
    /// raised *is* the plan approval, so allowing it starts the work.
    public static let approvePlan = ApprovalReply(decision: .allow,
                                                  reason: "Plan approved from Roost")

    /// Sending a plan back leaves the session in plan mode, where it can ask
    /// what to change. The island has nowhere to type the answer, so it says
    /// so rather than inventing feedback nobody gave.
    public static let revisePlan = ApprovalReply(
        decision: .deny,
        reason: "The user sent the plan back from Roost without written feedback. "
              + "Stay in plan mode and ask what to change.")
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
        "SlashCommand", "ListMcpResources",
    ]

    /// Calls that are a question to the person by nature. Held in every mode,
    /// because no permission setting answers them: `bypassPermissions` skips
    /// prompts, it does not decide which deploy target you meant.
    public static let asks: Set<String> = ["AskUserQuestion", "ExitPlanMode"]

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
        guard !asks.contains(tool) else { return true }
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

    /// How many answers a card has room for. `AskUserQuestion` offers between
    /// two and four, so this is headroom rather than a real ceiling.
    public static let maxOptions = 5

    /// The question behind an `AskUserQuestion`, or nil when the island has no
    /// business answering it.
    ///
    /// Deliberately narrow. One single-choice question is a card with buttons
    /// on it; several questions, or one that takes several answers, is a form,
    /// and half an answer sent back as a denial is worse than letting the
    /// session ask the way it always did.
    public static func question(from input: [String: Any]?) -> HeldQuestion? {
        guard let questions = input?["questions"] as? [[String: Any]],
              questions.count == 1,
              let asked = questions.first,
              asked["multiSelect"] as? Bool != true,
              let prompt = asked["question"] as? String, !prompt.isEmpty,
              let raw = asked["options"] as? [[String: Any]],
              (1...maxOptions).contains(raw.count)
        else { return nil }

        let options = raw.compactMap { option -> HeldQuestion.Option? in
            guard let label = option["label"] as? String, !label.isEmpty else { return nil }
            return HeldQuestion.Option(label: label,
                                       description: option["description"] as? String)
        }
        // An option that could not be read is an option nobody can pick, and a
        // card missing one of its answers is worse than no card.
        guard options.count == raw.count else { return nil }
        return HeldQuestion(prompt: prompt,
                            header: (asked["header"] as? String).flatMap { $0.isEmpty ? nil : $0 },
                            options: options)
    }

    /// What a session row shows for a held question: the question itself, cut
    /// to a row the way every other detail is.
    public static func summary(of question: HeldQuestion) -> String? {
        TranscriptReader.condensed(question.prompt)
    }

    /// The plan behind an `ExitPlanMode`, or nil when there is nothing to read.
    ///
    /// A verdict on a plan nobody can see is a guess, so an empty one is left
    /// to prompt where the plan is actually printed.
    public static func plan(from input: [String: Any]?) -> String? {
        guard let plan = input?["plan"] as? String,
              !plan.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        return plan
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
