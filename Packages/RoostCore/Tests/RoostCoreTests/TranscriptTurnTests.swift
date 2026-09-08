import XCTest
@testable import RoostCore

/// Where one turn ends and the next begins.
///
/// A transcript says a turn *ended* -- `stop_reason: end_turn` -- and never says
/// one started. The person pressing return is the only evidence of that, and it
/// arrives as an ordinary `user` record among the tool results.
final class TranscriptTurnTests: XCTestCase {
    private let at = "2026-09-08T12:00:00.000Z"
    private lazy var now = TranscriptReader.parseTimestamp(at)!

    // MARK: - Records

    private func endTurn(sidechain: Bool = false) -> String {
        """
        {"type":"assistant","timestamp":"\(at)"\(sidechain ? ",\"isSidechain\":true" : ""),\
        "message":{"stop_reason":"end_turn","content":[{"type":"text","text":"done"}]}}
        """
    }

    private func toolUse(_ id: String, _ name: String = "Bash") -> String {
        """
        {"type":"assistant","timestamp":"\(at)","message":{"stop_reason":"tool_use",\
        "content":[{"type":"tool_use","id":"\(id)","name":"\(name)",\
        "input":{"command":"swift build"}}]}}
        """
    }

    private func toolResult(_ id: String) -> String {
        """
        {"type":"user","timestamp":"\(at)","message":{"content":\
        [{"type":"tool_result","tool_use_id":"\(id)"}]}}
        """
    }

    private func prompt(_ text: String = "do the thing") -> String {
        #"{"type":"user","timestamp":"\#(at)","message":{"content":"\#(text)"}}"#
    }

    /// A prompt with something pasted into it, which is a list of blocks and
    /// still the person speaking.
    private func promptWithImage() -> String {
        """
        {"type":"user","timestamp":"\(at)","message":{"content":\
        [{"type":"image"},{"type":"text","text":"look at this"}]}}
        """
    }

    private func reading(_ lines: [String]) -> TranscriptReader.Reading {
        let url = FileManager.default.temporaryDirectory
            .appending(path: "\(UUID().uuidString).jsonl")
        try? lines.joined(separator: "\n").write(to: url, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: url) }
        return TranscriptReader.read(url: url, now: now)!
    }

    // MARK: - A turn that has started

    /// The regression this file exists for. Between pressing return and the
    /// model's first message there is nothing in the transcript but the prompt,
    /// and the turn before it said `end_turn`.
    func testAPromptAfterAFinishedTurnIsRunning() {
        XCTAssertEqual(reading([endTurn(), prompt()]).state, .running)
    }

    func testAPastedPromptCountsTheSame() {
        XCTAssertEqual(reading([endTurn(), promptWithImage()]).state, .running)
    }

    /// The tool the last turn happened to end on is not what this one is doing.
    func testAPromptClearsTheToolTheRowWasShowing() {
        let reading = self.reading([toolUse("t1"), toolResult("t1"), endTurn(), prompt()])
        XCTAssertEqual(reading.state, .running)
        XCTAssertNil(reading.activity)
        XCTAssertNil(reading.detail)
    }

    /// A result is a user record too, and it is the middle of a turn.
    func testAToolResultDoesNotStartATurn() {
        XCTAssertEqual(reading([toolUse("t1"), toolResult("t1"), endTurn()]).state, .done)
    }

    func testAPromptIsNotNeededToStayDone() {
        XCTAssertEqual(reading([endTurn()]).state, .done)
    }

    // MARK: - A turn that has ended

    /// A call the turn walked away from -- an interrupt, a crash -- used to
    /// outrank the `end_turn` that came after it and hold the session at
    /// `running`, then at `stalled` once the grace period passed.
    func testAnAbandonedCallDoesNotSurviveTheTurnItWasIn() {
        XCTAssertEqual(reading([toolUse("t1"), endTurn()]).state, .done)
    }

    func testAnAbandonedCallDoesNotSurviveTheNextPromptEither() {
        let reading = self.reading([toolUse("t1"), prompt()])
        XCTAssertEqual(reading.state, .running)
        XCTAssertNil(reading.activity)
    }

    /// The live case, which must keep working: a call with nothing after it.
    func testACallStillOutstandingIsStillPending() {
        let reading = self.reading([toolUse("t1")])
        XCTAssertEqual(reading.state, .running)
        XCTAssertEqual(reading.activity, "Bash")
        XCTAssertEqual(reading.detail, "swift build")
    }

    func testAQuestionStillBlocksOnSight() {
        XCTAssertEqual(reading([toolUse("t1", "AskUserQuestion")]).state, .blocked(.question))
    }

    // MARK: - Sub-agents

    /// A sub-agent's turns are written into the same file. Its `end_turn` says
    /// the sub-agent has finished, not that the session has, and the `Task` call
    /// waiting on it is still what the session is doing.
    func testASubAgentEndingItsTurnDoesNotEndTheSessions() {
        let reading = self.reading([toolUse("t1", "Task"), endTurn(sidechain: true)])
        XCTAssertEqual(reading.state, .running)
        XCTAssertEqual(reading.activity, "Task")
    }

    func testTheSessionsOwnEndTurnStillEndsIt() {
        XCTAssertEqual(reading([toolUse("t1", "Task"), endTurn(sidechain: true), endTurn()]).state,
                       .done)
    }
}

/// Which of several calls in flight the row is talking about.
extension TranscriptTurnTests {
    private func toolUse(_ id: String, _ name: String, at stamp: String) -> String {
        """
        {"type":"assistant","timestamp":"\(stamp)","message":{"stop_reason":"tool_use",\
        "content":[{"type":"tool_use","id":"\(id)","name":"\(name)","input":{"command":"\(id)"}}]}}
        """
    }

    /// A turn can have several calls outstanding at once. The row has to name
    /// the same one every tick, and the grace period has to count from the call
    /// that has actually been waiting -- not from whichever the dictionary
    /// yielded first that time round.
    func testTheOldestOutstandingCallIsTheOneReported() {
        let early = "2026-09-08T11:59:00.000Z"
        let late = "2026-09-08T11:59:50.000Z"
        for _ in 0..<12 {
            let reading = self.reading([toolUse("a", "Grep", at: late),
                                        toolUse("b", "Bash", at: early),
                                        toolUse("c", "Read", at: late)])
            // 60s outstanding, so the oldest is past the grace period and the
            // other two are not: picking either of them would read as running.
            XCTAssertEqual(reading.state, .blocked(.stalledTool(name: "Bash")))
            XCTAssertEqual(reading.detail, "b")
        }
    }
}
