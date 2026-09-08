import Foundation
import RoostCore

/// The `PreToolUse` hook. Reads Claude Code's payload on stdin, asks Roost
/// whether the call is allowed -- or which answer was picked -- and prints a
/// decision it can act on.
///
/// Every path out of here is exit 0 with no output unless there is a real
/// answer: a hook that says nothing leaves the session prompting exactly as it
/// did before, which is what must happen whenever Roost is not there to ask.
func runPreToolUse() -> Never {
    let payload = FileHandle.standardInput.readDataToEndOfFile()

    guard let json = try? JSONSerialization.jsonObject(with: payload) as? [String: Any],
          let tool = json["tool_name"] as? String,
          ApprovalGate.mayPrompt(tool: tool) else { exit(0) }

    let input = json["tool_input"] as? [String: Any]

    // Anything the island cannot put on a card in full it must not intercept:
    // the session asks the way it always did.
    var kind = HeldKind.permission
    // What the row shows under the title. For a question or a plan that is the
    // thing being asked; the keyed lookup below knows nothing about either.
    var detail = ApprovalGate.detail(tool: tool, input: input)

    switch tool {
    case "AskUserQuestion":
        guard let question = ApprovalGate.question(from: input) else { exit(0) }
        kind = .question(question)
        detail = ApprovalGate.summary(of: question)
    case "ExitPlanMode":
        guard let plan = ApprovalGate.plan(from: input) else { exit(0) }
        kind = .plan(plan)
        detail = PlanPreview.make(plan, limit: 1).lines.first
    default:
        break
    }

    // `agent_type` alone also describes a whole session started with --agent, so
    // the id is what says this particular call came from inside a sub-agent.
    let agent = json["agent_id"] == nil ? nil : json["agent_type"] as? String

    let request = ApprovalRequest(
        sessionId: json["session_id"] as? String ?? "",
        cwd: json["cwd"] as? String ?? FileManager.default.currentDirectoryPath,
        tool: tool,
        detail: detail,
        agent: agent,
        kind: kind)

    guard let reply = ApprovalClient.ask(request), reply.decision != .ask else { exit(0) }

    let output: [String: Any] = [
        "hookSpecificOutput": [
            "hookEventName": "PreToolUse",
            "permissionDecision": reply.decision.rawValue,
            "permissionDecisionReason": reply.reason ?? "Answered from the island",
        ],
    ]
    if let data = try? JSONSerialization.data(withJSONObject: output) {
        FileHandle.standardOutput.write(data)
    }
    exit(0)
}
