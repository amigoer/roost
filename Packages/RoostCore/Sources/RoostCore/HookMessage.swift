import Foundation

/// Everything a helper says to the app, down the one socket.
///
/// A held call waits for an answer; a usage report does not. They are the same
/// line-delimited JSON either way, so one envelope keeps the server from having
/// to guess what it just read.
public enum HookMessage: Codable, Sendable {
    case approval(ApprovalRequest)
    case usage(Usage)
    /// Where a session got to, from an agent that writes no registry Roost can
    /// read. Waits for nothing.
    case session(SessionReport)
}

extension HookMessage {
    /// Reads a frame, falling back to a bare request.
    ///
    /// A bundle can be left holding an older `roost-hook`, and one already
    /// running has a session stopped behind it. Refusing to understand it
    /// would strand that session for the full timeout.
    public static func decode(_ line: Data) -> HookMessage? {
        if let message = try? JSONDecoder.wire.decode(HookMessage.self, from: line) {
            return message
        }
        return (try? JSONDecoder.wire.decode(ApprovalRequest.self, from: line)).map(Self.approval)
    }
}
