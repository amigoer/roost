import Foundation

/// What a helper prints so the agent acts on the answer.
///
/// Two events, two shapes, and getting either wrong fails the same silent way:
/// the agent rejects the output, prompts as it always did, and nothing says so.
/// Which is why this lives here, in reach of a test, rather than inline in a
/// binary nothing can call.
public enum HookOutput {
    /// The event whose answer *is* the permission decision.
    public static let permissionRequest = "PermissionRequest"

    public static func body(_ reply: ApprovalReply, for event: String) -> [String: Any] {
        event == permissionRequest ? decision(reply) : legacy(reply, for: event)
    }

    public static func data(_ reply: ApprovalReply, for event: String) -> Data? {
        try? JSONSerialization.data(withJSONObject: body(reply, for: event))
    }

    /// `PermissionRequest` takes a verdict object. The two documented forms are
    /// `{"behavior": "allow"}` and `{"behavior": "deny", "message": …}`, so a
    /// reason is attached only where there is a form that carries one.
    private static func decision(_ reply: ApprovalReply) -> [String: Any] {
        var verdict: [String: Any] = ["behavior": reply.decision.rawValue]
        if reply.decision == .deny {
            verdict["message"] = reply.reason ?? "Denied from the island"
        }
        return ["hookSpecificOutput": ["hookEventName": permissionRequest, "decision": verdict]]
    }

    /// `PreToolUse` takes a decision and a reason, and the reason is the only
    /// thing a session ever reads back from one -- which is what makes it the
    /// way to answer a question or send a plan back.
    private static func legacy(_ reply: ApprovalReply, for event: String) -> [String: Any] {
        ["hookSpecificOutput": [
            "hookEventName": event,
            "permissionDecision": reply.decision.rawValue,
            "permissionDecisionReason": reply.reason ?? "Answered from the island",
        ]]
    }
}
