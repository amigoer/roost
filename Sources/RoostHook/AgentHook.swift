import Foundation
import RoostCore

/// The hook for an agent that is not Claude Code.
///
/// Two jobs down one entry point, told apart by the event name. The permission
/// event waits for an answer the way the Claude Code hook does; everything else
/// only says where the session got to, and waits for nothing.
///
/// Silence is the safe answer here as well: an agent that gets nothing back
/// prompts exactly as it always did.
func runAgentHook(_ agent: AgentKind) -> Never {
    let payload = FileHandle.standardInput.readDataToEndOfFile()

    guard let json = try? JSONSerialization.jsonObject(with: payload) as? [String: Any],
          let event = json["hook_event_name"] as? String else { exit(0) }

    let sessionId = json["session_id"] as? String ?? ""
    let cwd = json["cwd"] as? String ?? FileManager.default.currentDirectoryPath
    let tool = json["tool_name"] as? String
    let detail = ApprovalGate.detail(tool: tool ?? "", input: json["tool_input"] as? [String: Any])

    guard event == agent.permissionEvent else {
        ApprovalClient.report(SessionReport(
            source: agent, sessionId: sessionId, cwd: cwd, event: event,
            tool: tool, detail: detail, model: json["model"] as? String,
            // The agent and its terminal are still there when the row is
            // clicked. This hook is not, so it hands over its own chain.
            ancestors: ProcessTree.ancestors(of: getpid())))
        exit(0)
    }

    // No permission mode to weigh: this event fires only where a prompt was
    // really about to appear, which is the whole reason to prefer it.
    let request = ApprovalRequest(sessionId: sessionId, cwd: cwd, tool: tool ?? "tool",
                                  detail: detail, source: agent)
    guard let reply = ApprovalClient.ask(request), reply.decision != .ask else { exit(0) }

    let output: [String: Any] = [
        "hookSpecificOutput": [
            "hookEventName": agent.permissionEvent,
            "decision": [
                "behavior": reply.decision.rawValue,
                "message": reply.reason ?? "Answered from the island",
            ],
        ],
    ]
    if let data = try? JSONSerialization.data(withJSONObject: output) {
        FileHandle.standardOutput.write(data)
    }
    exit(0)
}
