import XCTest
@testable import RoostCore

/// What a hook adds to a session Roost can already see.
///
/// Claude Code's transcript is the better record of what a session is doing and
/// the worse record of when it stopped doing it: the turn's last message is not
/// written until the model has finished writing it. The hook fires at the
/// boundary. These pin which one wins, and what it is allowed to change.
@MainActor
final class TurnMarkTests: XCTestCase {
    private let start = Date(timeIntervalSince1970: 1_000_000)

    private func session(state: SessionState, lastActivity: TimeInterval,
                         activity: String? = "Bash") -> Session {
        Session(id: "s1", pid: 1, name: "roost", cwd: "/tmp/roost", entrypoint: nil,
                startedAt: start, state: state, stateSince: start,
                activity: activity, detail: "swift build",
                lastActivityAt: start.addingTimeInterval(lastActivity))
    }

    private func mark(_ event: String, at offset: TimeInterval) -> [String: ReportedSessions.TurnMark] {
        ["s1": ReportedSessions.TurnMark(event: event, at: start.addingTimeInterval(offset))]
    }

    /// The case this exists for: the model has stopped, the answer is on
    /// screen, and the transcript will not say so for another fifteen seconds.
    func testAStopAfterTheLastWrittenLineEndsTheTurn() {
        let sharpened = ReportedSessions.sharpened(
            [session(state: .running, lastActivity: 0)], by: mark("Stop", at: 15))
        XCTAssertEqual(sharpened[0].state, .done)
        XCTAssertEqual(sharpened[0].lastActivityAt, start.addingTimeInterval(15))
    }

    /// A finished turn is not still running a tool, and the row must not go on
    /// naming the last one it saw.
    func testEndingATurnClearsWhatTheRowWasDoing() {
        let sharpened = ReportedSessions.sharpened(
            [session(state: .running, lastActivity: 0)], by: mark("Stop", at: 15))
        XCTAssertNil(sharpened[0].activity)
        XCTAssertNil(sharpened[0].detail)
    }

    /// The transcript advances with every tool call, so a mark from the top of
    /// the turn goes stale within seconds. Whichever spoke last wins.
    func testAStaleMarkLosesToTheTranscript() {
        let sharpened = ReportedSessions.sharpened(
            [session(state: .running, lastActivity: 40)], by: mark("Stop", at: 15))
        XCTAssertEqual(sharpened[0].state, .running)
        XCTAssertEqual(sharpened[0].activity, "Bash")
    }

    func testAPromptStartsTheTurnWithoutWaitingForTheFile() {
        let sharpened = ReportedSessions.sharpened(
            [session(state: .done, lastActivity: 0, activity: nil)],
            by: mark("UserPromptSubmit", at: 3))
        XCTAssertEqual(sharpened[0].state, .running)
    }

    /// Everything else an agent announces is about a tool, which the file
    /// describes better than the payload does.
    func testAnythingButABoundaryIsIgnored() {
        let sharpened = ReportedSessions.sharpened(
            [session(state: .running, lastActivity: 0)], by: mark("PostToolUse", at: 15))
        XCTAssertEqual(sharpened[0].state, .running)
        XCTAssertEqual(sharpened[0].lastActivityAt, start)
    }

    func testAMarkForSomebodyElsesSessionChangesNothing() {
        let marks = ["other": ReportedSessions.TurnMark(event: "Stop",
                                                        at: start.addingTimeInterval(15))]
        let sharpened = ReportedSessions.sharpened([session(state: .running, lastActivity: 0)],
                                                   by: marks)
        XCTAssertEqual(sharpened[0].state, .running)
    }

    /// A row for a Claude Code session comes from the registry. Repeating it
    /// out of the hook log would outlive the process by twelve hours.
    func testAnAgentWithARegistryNeverGetsARowOfItsOwn() {
        let reported = ReportedSessions()
        reported.receive(SessionReport(source: .claudeCode, sessionId: "s1", cwd: "/tmp/roost",
                                       event: "UserPromptSubmit"))
        XCTAssertTrue(reported.sessions().isEmpty)
        XCTAssertEqual(reported.turnMarks()["s1"]?.event, "UserPromptSubmit")
    }

    /// Codex has no registry, so its rows exist only because its hooks said so.
    func testAnAgentWithoutOneStillGetsARow() {
        let reported = ReportedSessions()
        reported.receive(SessionReport(source: .codex, sessionId: "c1", cwd: "/tmp/x",
                                       event: "UserPromptSubmit"))
        XCTAssertEqual(reported.sessions().count, 1)
        XCTAssertTrue(reported.turnMarks().isEmpty)
    }

    /// The migration path: the switch is already on, and turning it on today
    /// would write two more events than it used to.
    func testTurningItOnNowWiresTheBoundariesToo() {
        let written = HookInstall.adding(agent: .claudeCode, command: "/x/roost-hook", to: [:])
        for event in ["PermissionRequest", "PreToolUse", "UserPromptSubmit", "Stop"] {
            XCTAssertTrue(HookInstall.isInstalled(written, command: "/x/roost-hook", event: event),
                          "\(event) should be wired")
        }
    }

    /// Adding them must not flip the switch's own answer, which is what the
    /// settings pane reads and what decides whether a repair even runs.
    func testTheSwitchStillReadsAsOnFromAnOlderInstall() {
        var older = HookInstall.adding(command: "/x/roost-hook", to: [:], event: "PreToolUse")
        older = HookInstall.adding(command: "/x/roost-hook", to: older, event: "PermissionRequest")
        XCTAssertTrue(HookInstall.isInstalled(agent: .claudeCode, command: "/x/roost-hook",
                                              in: older))
    }
}
