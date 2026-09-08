import Foundation
import RoostCore

// The PreToolUse hook. Reads Claude Code's payload on stdin, asks Roost whether
// the call is allowed, and prints a decision it can act on.
//
// Every path out of here is exit 0 with no output unless there is a real
// answer: a hook that says nothing leaves the session prompting exactly as it
// did before, which is what must happen whenever Roost is not there to ask.

let payload = FileHandle.standardInput.readDataToEndOfFile()

guard let json = try? JSONSerialization.jsonObject(with: payload) as? [String: Any],
      let tool = json["tool_name"] as? String,
      ApprovalGate.mayPrompt(tool: tool) else { exit(0) }

// `agent_type` alone also describes a whole session started with --agent, so
// the id is what says this particular call came from inside a sub-agent.
let agent = json["agent_id"] == nil ? nil : json["agent_type"] as? String

let request = ApprovalRequest(
    sessionId: json["session_id"] as? String ?? "",
    cwd: json["cwd"] as? String ?? FileManager.default.currentDirectoryPath,
    tool: tool,
    detail: ApprovalGate.detail(tool: tool, input: json["tool_input"] as? [String: Any]),
    agent: agent)

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
