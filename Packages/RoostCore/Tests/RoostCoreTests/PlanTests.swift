import XCTest
@testable import RoostCore

final class PlanPreviewTests: XCTestCase {
    func testHeadingsLoseTheirHashes() {
        XCTAssertEqual(PlanPreview.flatten("## Approach"), ["Approach"])
    }

    func testEveryListMarkerBecomesTheSameBullet() {
        let flattened = PlanPreview.flatten("""
        - read the transcript
        * write the card
        + wire the hit test
        1. ship it
        2) then rest
        """)
        XCTAssertEqual(flattened, ["• read the transcript", "• write the card",
                                   "• wire the hit test", "• ship it", "• then rest"])
    }

    func testEmphasisAndFencesAreSpentOnWords() {
        XCTAssertEqual(PlanPreview.flatten("""
        ```swift
        let x = 1
        ```
        Use **NSPanel** and `orderFrontRegardless`.
        """),
        ["let x = 1", "Use NSPanel and orderFrontRegardless."])
    }

    func testBlankLinesAreNotLines() {
        XCTAssertEqual(PlanPreview.flatten("one\n\n\n   \ntwo"), ["one", "two"])
    }

    /// A digit at the start of a sentence is not a list.
    func testANumberThatIsNotAListStaysAsWritten() {
        XCTAssertEqual(PlanPreview.flatten("2026 was the year"), ["2026 was the year"])
    }

    func testALongLineIsCutRatherThanWrapped() {
        let line = String(repeating: "a", count: PlanPreview.lineLimit + 40)
        let flattened = PlanPreview.flatten(line)
        XCTAssertEqual(flattened.first?.count, PlanPreview.lineLimit)
        XCTAssertEqual(flattened.first?.hasSuffix("…"), true)
    }

    func testTheCardSaysHowMuchItCouldNotShow() {
        let plan = (1...10).map { "step \($0)" }.joined(separator: "\n")
        let preview = PlanPreview.make(plan, limit: 4)
        XCTAssertEqual(preview.lines, ["step 1", "step 2", "step 3", "step 4"])
        XCTAssertEqual(preview.remaining, 6)
    }

    func testAPlanThatFitsHasNothingLeftOver() {
        XCTAssertEqual(PlanPreview.make("one\ntwo", limit: 6).remaining, 0)
    }
}

final class PlanGateTests: XCTestCase {
    func testAPlanReachesTheIslandInEveryMode() {
        for mode in [nil, "default", "acceptEdits", "auto", "bypassPermissions", "plan"] {
            XCTAssertTrue(ApprovalGate.shouldAsk(tool: "ExitPlanMode", permissionMode: mode),
                          "mode \(mode ?? "nil")")
        }
    }

    /// A verdict on a plan nobody can see is a guess.
    func testAnEmptyPlanIsLeftToPromptWhereItIsPrinted() {
        XCTAssertNil(ApprovalGate.plan(from: ["plan": "   \n "]))
        XCTAssertNil(ApprovalGate.plan(from: [:]))
        XCTAssertNil(ApprovalGate.plan(from: nil))
    }

    func testTheRowSaysTheSessionIsWaitingOnAPlan() {
        let request = ApprovalRequest(sessionId: "s", cwd: "/tmp/perch", tool: "ExitPlanMode",
                                      detail: "Approach", kind: .plan("## Approach"))
        XCTAssertEqual(request.blockReason, .planApproval)
    }

    /// Approving is letting the call run: the prompt it would have raised is
    /// the plan approval itself.
    func testApprovingStartsTheWorkAndRevisingDoesNot() {
        XCTAssertEqual(ApprovalReply.approvePlan.decision, .allow)
        XCTAssertEqual(ApprovalReply.revisePlan.decision, .deny)
        XCTAssertEqual(ApprovalReply.revisePlan.reason?.contains("plan mode"), true)
    }
}

final class PlanGeometryTests: XCTestCase {
    private let notch = CGSize(width: 190, height: 38)
    private let width = IslandGeometry.expandedWidth

    private var buttonMiddle: CGFloat {
        IslandGeometry.heldTop(notch: notch) + IslandGeometry.Held.planHeaderHeight
            + CGFloat(IslandGeometry.Held.planLines) * IslandGeometry.Held.planLineHeight
            + IslandGeometry.Held.planButtonsHeight / 2
    }

    func testApproveIsTheRightmostButton() {
        let x = width - IslandGeometry.Approval.trailingInset - IslandGeometry.Approval.buttonWidth / 2
        XCTAssertEqual(IslandGeometry.planHit(offsetFromTop: buttonMiddle, offsetFromLeft: x,
                                              notch: notch, islandWidth: width), .allow)
    }

    func testReviseSitsLeftOfApprove() {
        let allowStart = width - IslandGeometry.Approval.trailingInset - IslandGeometry.Approval.buttonWidth
        let deny = allowStart - IslandGeometry.Approval.gap - IslandGeometry.Approval.buttonWidth / 2
        XCTAssertEqual(IslandGeometry.planHit(offsetFromTop: buttonMiddle, offsetFromLeft: deny,
                                              notch: notch, islandWidth: width), .deny)
    }

    /// The plan itself is text, not a target: clicking a line must decide
    /// nothing.
    func testThePlanTextDecidesNothing() {
        let x = width - IslandGeometry.Approval.trailingInset - IslandGeometry.Approval.buttonWidth / 2
        let inThePlan = IslandGeometry.heldTop(notch: notch)
            + IslandGeometry.Held.planHeaderHeight + 4
        XCTAssertNil(IslandGeometry.planHit(offsetFromTop: inThePlan, offsetFromLeft: x,
                                            notch: notch, islandWidth: width))
    }

    func testTheRowsStartBelowThePlan() {
        let card = IslandGeometry.Held.height(.plan("## Approach"))
        XCTAssertEqual(card, IslandGeometry.Held.planHeight)
        let firstRow = IslandGeometry.rowsTopInset(notch: notch, heldHeight: card) + 4
        XCTAssertEqual(IslandGeometry.rowIndex(atOffsetFromTop: firstRow, notch: notch,
                                               rowCount: 2, heldHeight: card), 0)
        XCTAssertNil(IslandGeometry.planHit(offsetFromTop: firstRow, offsetFromLeft: width - 40,
                                            notch: notch, islandWidth: width))
    }
}

@MainActor
final class PlanVerdictTests: XCTestCase {
    private let held = ApprovalRequest(sessionId: "s", cwd: "/tmp/perch", tool: "ExitPlanMode",
                                       detail: "Approach", kind: .plan("## Approach\n- do it"))

    func testApprovingReleasesTheCallToRun() async {
        let center = ApprovalCenter()
        let answered = Task { await center.handle(held) }
        try? await Task.sleep(for: .milliseconds(30))

        center.decide(held.id, .allow)
        let reply = await answered.value
        XCTAssertEqual(reply.decision, .allow)
        XCTAssertTrue(center.pending.isEmpty)
    }

    func testRevisingSendsItBackWithSomethingToActOn() async {
        let center = ApprovalCenter()
        let answered = Task { await center.handle(held) }
        try? await Task.sleep(for: .milliseconds(30))

        center.decide(held.id, .deny)
        let reply = await answered.value
        XCTAssertEqual(reply.decision, .deny)
        XCTAssertEqual(reply.reason?.contains("ask what to change"), true)
    }
}
