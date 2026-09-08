import Foundation
import Observation

/// The held tool calls, and the answers going back to them.
@MainActor
@Observable
public final class ApprovalCenter {
    public init() {}

    public private(set) var pending: [ApprovalRequest] = []

    /// Looks up a session's permission mode. A tool that would not have
    /// prompted must not produce a card: an interruption nobody asked for is
    /// worse than a missed chance to approve early.
    ///
    /// Asked at the moment of a hold, and allowed to take its time about it:
    /// a mode read minutes ago describes a session that may have changed it
    /// since, and being wrong here is what puts a card on screen for a call
    /// nobody was ever going to be asked about.
    @ObservationIgnored public var permissionMode: ((String) async -> String?)?

    @ObservationIgnored private var waiters: [String: CheckedContinuation<ApprovalReply, Never>] = [:]

    /// The island answers one at a time, oldest first: the session behind it
    /// has been stopped the longest.
    public var current: ApprovalRequest? { pending.first }

    public func handle(_ request: ApprovalRequest) async -> ApprovalReply {
        // A question is held in every mode, so reading the mode would only be
        // a disk hit on the way to the same answer.
        if case .permission = request.kind {
            guard await ApprovalGate.shouldAsk(
                tool: request.tool,
                permissionMode: permissionMode?(request.sessionId)) else {
                return ApprovalReply(decision: .ask)
            }
        }
        pending.append(request)
        return await withCheckedContinuation { continuation in
            waiters[request.id] = continuation
        }
    }

    public func decide(_ id: String, _ decision: ApprovalDecision) {
        reply(id, ApprovalReply(decision: decision,
                                reason: decision == .allow ? "Allowed from the island"
                                                           : "Denied from the island"))
    }

    /// Picks one of a question's options by position, the way the card is read.
    ///
    /// Silently does nothing for an index the question does not have: the card
    /// and the hit test derive their layout separately, and a click that lands
    /// between them must not send an answer nobody chose.
    public func answer(_ id: String, option index: Int) {
        guard let request = pending.first(where: { $0.id == id }),
              case .question(let question) = request.kind,
              question.options.indices.contains(index) else { return }
        reply(id, .answer(question.options[index].label))
    }

    private func reply(_ id: String, _ reply: ApprovalReply) {
        pending.removeAll { $0.id == id }
        waiters.removeValue(forKey: id)?.resume(returning: reply)
    }

    /// The hook stops waiting on its own schedule, so a card nobody answered
    /// has to disappear on the same one, or the island lies about what is held.
    public func expireStale(now: Date = Date()) {
        let stale = pending
            .filter { now.timeIntervalSince($0.receivedAt) > ApprovalSocket.timeout }
            .map(\.id)
        for id in stale {
            reply(id, ApprovalReply(decision: .ask))
        }
    }
}
