import Foundation
import RoostCore

/// The hook that stands between an agent and the person.
///
/// One entry point for every tool event, told apart by the name the payload
/// carries:
///
/// - `PermissionRequest` runs where a permission prompt is about to appear and
///   nowhere else, so what arrives is already exactly what is worth a card.
///   Nothing is inferred and nothing is filtered.
/// - `PreToolUse` runs for every call, and is kept only for the two that stop a
///   session without being permissions at all: a question and a plan. Anything
///   else it brings is dropped here, so the common path costs one set lookup.
/// - Everything else only says where a session got to, and only for an agent
///   with no registry of its own to read.
///
/// Every path out is exit 0 with no output unless there is a real answer: a
/// hook that says nothing leaves the session prompting exactly as it did.
func runToolHook(_ agent: AgentKind) -> Never {
    let payload = FileHandle.standardInput.readDataToEndOfFile()

    guard let json = try? JSONSerialization.jsonObject(with: payload) as? [String: Any],
          let event = json["hook_event_name"] as? String else { exit(0) }

    let tool = json["tool_name"] as? String
    let input = json["tool_input"] as? [String: Any]
    let sessionId = json["session_id"] as? String ?? ""
    let cwd = json["cwd"] as? String ?? FileManager.default.currentDirectoryPath
    let detail = ApprovalGate.detail(tool: tool ?? "", input: input)

    // `agent_type` alone also describes a whole session started with --agent, so
    // the id is what says this particular call came from inside a sub-agent.
    let subagent = json["agent_id"] == nil ? nil : json["agent_type"] as? String

    func hold(_ kind: HeldKind) -> Never {
        let request = ApprovalRequest(sessionId: sessionId, cwd: cwd, tool: tool ?? "tool",
                                      detail: ApprovalGate.summary(of: kind) ?? detail,
                                      agent: subagent, kind: kind)
        guard let reply = ApprovalClient.ask(request), reply.decision != .ask,
              let answer = HookOutput.data(reply, for: event) else { exit(0) }
        FileHandle.standardOutput.write(answer)
        exit(0)
    }

    if let tool {
        switch event {
        case HookOutput.permissionRequest:
            // A question and a plan reach the island through PreToolUse, and
            // one stop deserves exactly one card.
            guard !ApprovalGate.asks.contains(tool) else { exit(0) }
            hold(.permission)
        case "PreToolUse":
            if let kind = ApprovalGate.ask(tool: tool, input: input) { hold(kind) }
        default:
            break
        }
    }

    // An agent with a registry and transcripts of its own is read rather than
    // told, and a second row for a session already listed is worse than none.
    guard agent.lifecycleEvents.contains(event) else { exit(0) }

    ApprovalClient.report(SessionReport(
        source: agent, sessionId: sessionId, cwd: cwd, event: event,
        tool: tool, detail: detail, model: json["model"] as? String,
        // The agent and its terminal are still there when the row is clicked.
        // This hook is not, so it hands over its own chain.
        ancestors: ProcessTree.ancestors(of: getpid())))
    exit(0)
}
