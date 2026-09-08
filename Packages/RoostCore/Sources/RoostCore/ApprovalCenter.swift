import Foundation
import Observation

/// The held tool calls, and the answers going back to them.
@MainActor
@Observable
public final class ApprovalCenter {
    public init() {}

    public private(set) var pending: [ApprovalRequest] = []

    /// Called the moment a call is actually held, for anything that has to
    /// react to it sooner than the next scan does.
    @ObservationIgnored public var onHold: ((ApprovalRequest) -> Void)?

    @ObservationIgnored private var waiters: [String: CheckedContinuation<ApprovalReply, Never>] = [:]

    /// The island answers one at a time, oldest first: the session behind it
    /// has been stopped the longest.
    public var current: ApprovalRequest? { pending.first }

    /// Everything that arrives here is held.
    ///
    /// Nothing is weighed on the way in any more: the helper only sends calls
    /// an agent was really about to prompt about, so a card here is a prompt
    /// there. What used to sit in this method -- reading a session's permission
    /// mode off disk to guess whether the prompt was real -- is what the
    /// `PermissionRequest` event replaced.
    public func handle(_ request: ApprovalRequest) async -> ApprovalReply {
        pending.append(request)
        onHold?(request)
        return await withCheckedContinuation { continuation in
            waiters[request.id] = continuation
        }
    }

    public func decide(_ id: String, _ decision: ApprovalDecision) {
        // A verdict on a plan is not a permission: allowing it starts the work,
        // and refusing it has to leave the session somewhere it can ask why.
        if case .plan = pending.first(where: { $0.id == id })?.kind {
            reply(id, decision == .allow ? .approvePlan : .revisePlan)
            return
        }
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

    /// Give the call back to the session it came from.
    ///
    /// Holding a call is also taking it away: while the island has it, the
    /// agent's own prompt does not appear, so there is exactly one place to
    /// answer and it is not the one the person is looking at. `ask` is the
    /// decision that means *I did not decide this*, and a session handed one
    /// prompts the way it always did.
    public func handBack(_ id: String) {
        reply(id, ApprovalReply(decision: .ask))
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
