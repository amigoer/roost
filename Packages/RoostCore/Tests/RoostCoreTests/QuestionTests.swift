import XCTest
@testable import RoostCore

final class QuestionParsingTests: XCTestCase {
    private func input(_ question: [String: Any]) -> [String: Any] {
        ["questions": [question]]
    }

    private let options: [[String: Any]] = [
        ["label": "date-fns", "description": "lightweight, tree-shakeable"],
        ["label": "Luxon", "description": "timezone-aware"],
    ]

    func testASingleChoiceQuestionBecomesACard() throws {
        let parsed = try XCTUnwrap(ApprovalGate.question(from: input([
            "question": "Which library should we use?",
            "header": "Library",
            "options": options,
        ])))
        XCTAssertEqual(parsed.prompt, "Which library should we use?")
        XCTAssertEqual(parsed.header, "Library")
        XCTAssertEqual(parsed.options.map(\.label), ["date-fns", "Luxon"])
        XCTAssertEqual(parsed.options.first?.description, "lightweight, tree-shakeable")
    }

    func testAMissingHeaderIsJustMissing() throws {
        let parsed = try XCTUnwrap(ApprovalGate.question(from: input([
            "question": "Which library?", "options": options,
        ])))
        XCTAssertNil(parsed.header)
    }

    /// Half an answer sent back as a denial is worse than letting the session
    /// ask the way it always did, so anything the card cannot fully answer is
    /// left alone.
    func testAQuestionTakingSeveralAnswersIsLeftToTheSession() {
        XCTAssertNil(ApprovalGate.question(from: input([
            "question": "Which features?", "multiSelect": true, "options": options,
        ])))
    }

    func testSeveralQuestionsAtOnceAreLeftToTheSession() {
        XCTAssertNil(ApprovalGate.question(from: [
            "questions": [
                ["question": "Which library?", "options": options],
                ["question": "Which runtime?", "options": options],
            ],
        ]))
    }

    /// A card missing one of its answers would quietly hide a choice, so an
    /// option that cannot be read takes the whole card down with it.
    func testAnUnreadableOptionCancelsTheCard() {
        XCTAssertNil(ApprovalGate.question(from: input([
            "question": "Which library?",
            "options": [["label": "date-fns"], ["description": "no label here"]],
        ])))
    }

    func testAQuestionWithNoOptionsIsNotACard() {
        XCTAssertNil(ApprovalGate.question(from: input([
            "question": "Which library?", "options": [],
        ])))
        XCTAssertNil(ApprovalGate.question(from: nil))
    }

    func testMoreOptionsThanTheCardHoldsIsLeftToTheSession() {
        let many = (0...ApprovalGate.maxOptions).map { ["label": "option \($0)"] }
        XCTAssertNil(ApprovalGate.question(from: input([
            "question": "Which one?", "options": many,
        ])))
    }

    /// No permission event fires for a question, so it reaches the island
    /// through `PreToolUse` and is claimed there by name.
    func testAQuestionIsClaimedFromPreToolUse() {
        XCTAssertTrue(ApprovalGate.asks.contains("AskUserQuestion"))
        XCTAssertNotNil(ApprovalGate.ask(tool: "AskUserQuestion", input: [
            "questions": [["question": "Which one?",
                           "options": [["label": "a"], ["label": "b"]]]],
        ]))
    }

    func testTheRowSaysTheSessionAskedRatherThanNeedsPermission() {
        let question = HeldQuestion(prompt: "Which library?",
                                    options: [HeldQuestion.Option(label: "date-fns")])
        let request = ApprovalRequest(sessionId: "s", cwd: "/tmp/perch", tool: "AskUserQuestion",
                                      detail: "Which library?", kind: .question(question))
        XCTAssertEqual(request.blockReason, .question)
    }

    /// Answering puts the choice in front of the model as a denial reason,
    /// which is the only thing a hook decision can carry back.
    func testAnAnswerCarriesTheLabel() {
        let reply = ApprovalReply.answer("Luxon")
        XCTAssertEqual(reply.decision, .deny)
        XCTAssertEqual(reply.reason?.contains("Luxon"), true)
    }
}

final class QuestionGeometryTests: XCTestCase {
    private let notch = CGSize(width: 190, height: 38)

    private func question(_ count: Int) -> HeldQuestion {
        HeldQuestion(prompt: "Which one?",
                     options: (0..<count).map { HeldQuestion.Option(label: "option \($0)") })
    }

    func testEachAnswerOwnsItsOwnBand() {
        let top = IslandGeometry.heldTop(notch: notch) + IslandGeometry.Held.promptHeight
        for index in 0..<3 {
            let middle = top + (CGFloat(index) + 0.5) * IslandGeometry.Held.optionHeight
            XCTAssertEqual(IslandGeometry.optionIndex(offsetFromTop: middle, notch: notch,
                                                      optionCount: 3), index)
        }
    }

    func testThePromptItselfAnswersNothing() {
        let middle = IslandGeometry.heldTop(notch: notch) + IslandGeometry.Held.promptHeight / 2
        XCTAssertNil(IslandGeometry.optionIndex(offsetFromTop: middle, notch: notch, optionCount: 3))
    }

    func testBelowTheLastAnswerIsNotAnAnswer() {
        let below = IslandGeometry.heldTop(notch: notch) + IslandGeometry.Held.promptHeight
            + 3 * IslandGeometry.Held.optionHeight + 1
        XCTAssertNil(IslandGeometry.optionIndex(offsetFromTop: below, notch: notch, optionCount: 3))
    }

    /// The rows start below the whole card, so a click meant for the first
    /// session cannot land on the last answer.
    func testTheRowsStartBelowEveryAnswer() {
        let card = IslandGeometry.Held.height(.question(question(4)))
        let firstRow = IslandGeometry.rowsTopInset(notch: notch, heldHeight: card) + 4
        XCTAssertEqual(IslandGeometry.rowIndex(atOffsetFromTop: firstRow, notch: notch,
                                               rowCount: 2, heldHeight: card), 0)
        XCTAssertNil(IslandGeometry.optionIndex(offsetFromTop: firstRow, notch: notch,
                                                optionCount: 4))
    }

    func testTheCardGrowsWithItsAnswers() {
        XCTAssertGreaterThan(IslandGeometry.Held.height(.question(question(4))),
                             IslandGeometry.Held.height(.question(question(2))))
        XCTAssertEqual(IslandGeometry.Held.height(nil), 0)
    }
}

@MainActor
final class AnsweringTests: XCTestCase {
    private func request(_ options: [String]) -> ApprovalRequest {
        ApprovalRequest(sessionId: "s", cwd: "/tmp/perch", tool: "AskUserQuestion",
                        detail: "Which one?",
                        kind: .question(HeldQuestion(
                            prompt: "Which one?",
                            options: options.map { HeldQuestion.Option(label: $0) })))
    }

    func testPickingAnOptionReleasesTheCall() async {
        let center = ApprovalCenter()
        let held = request(["date-fns", "Luxon"])
        let answered = Task { await center.handle(held) }
        try? await Task.sleep(for: .milliseconds(30))

        XCTAssertEqual(center.current?.id, held.id)
        center.answer(held.id, option: 1)

        let reply = await answered.value
        XCTAssertEqual(reply.decision, .deny)
        XCTAssertEqual(reply.reason?.contains("Luxon"), true)
        XCTAssertTrue(center.pending.isEmpty)
    }

    /// The card and the hit test derive their layout separately; a click that
    /// lands between them must not send an answer nobody chose.
    func testAnIndexTheQuestionDoesNotHaveIsIgnored() async {
        let center = ApprovalCenter()
        let held = request(["date-fns", "Luxon"])
        let answered = Task { await center.handle(held) }
        try? await Task.sleep(for: .milliseconds(30))

        center.answer(held.id, option: 7)
        XCTAssertEqual(center.pending.count, 1)

        center.answer(held.id, option: 0)
        _ = await answered.value
    }
}
