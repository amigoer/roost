import XCTest
@testable import RoostCore

final class AgentHookInstallTests: XCTestCase {
    private let command = "'/Applications/Roost.app/Contents/MacOS/roost-hook' --agent codex"

    private func hooks(_ settings: [String: Any]) -> [String: Any] {
        settings["hooks"] as? [String: Any] ?? [:]
    }

    func testCodexGetsThePromptEventAndEveryLifecycleOne() {
        let settings = HookInstall.adding(agent: .codex, command: command, to: [:])
        let installed = hooks(settings)
        for event in AgentKind.codex.answerEvents {
            XCTAssertNotNil(installed[event], event)
        }
        for event in AgentKind.codex.lifecycleEvents {
            XCTAssertNotNil(installed[event], event)
        }
        XCTAssertTrue(HookInstall.isInstalled(agent: .codex, command: command, in: settings))
    }

    /// Nothing waits on a lifecycle hook, so it must not be allowed to sit in
    /// the path of the thing it is describing for a minute.
    func testOnlyThePromptEventWaits() throws {
        let installed = hooks(HookInstall.adding(agent: .codex, command: command, to: [:]))
        func timeout(_ event: String) throws -> Int {
            let groups = try XCTUnwrap(installed[event] as? [[String: Any]])
            let entry = try XCTUnwrap((groups.first?["hooks"] as? [[String: Any]])?.first)
            return try XCTUnwrap(entry["timeout"] as? Int)
        }
        XCTAssertEqual(try timeout("PermissionRequest"), HookInstall.hookTimeout)
        XCTAssertEqual(try timeout("SessionStart"), HookInstall.reportTimeout)
        XCTAssertLessThan(HookInstall.reportTimeout, HookInstall.hookTimeout)
    }

    /// An entry left behind after an uninstall is a hook nobody can see and
    /// nobody asked for.
    func testRemovingSweepsEveryEvent() {
        let installed = HookInstall.adding(agent: .codex, command: command, to: [:])
        XCTAssertTrue(HookInstall.removing(command: command, from: installed).isEmpty)
    }

    func testOtherPeoplesHooksSurviveBothWays() throws {
        let theirs: [String: Any] = ["hooks": [
            "SessionStart": [["hooks": [["type": "command", "command": "/opt/theirs"]]]],
        ]]
        let installed = HookInstall.adding(agent: .codex, command: command, to: theirs)
        let removed = HookInstall.removing(command: command, from: installed)

        let groups = try XCTUnwrap((removed["hooks"] as? [String: Any])?["SessionStart"]
                                   as? [[String: Any]])
        XCTAssertEqual(groups.count, 1)
        XCTAssertFalse(HookInstall.isInstalled(agent: .codex, command: command, in: removed))
    }

    func testInstallingTwiceAddsNothingTwice() throws {
        let once = HookInstall.adding(agent: .codex, command: command, to: [:])
        let twice = HookInstall.adding(agent: .codex, command: command, to: once)
        let groups = try XCTUnwrap(hooks(twice)["SessionStart"] as? [[String: Any]])
        XCTAssertEqual(groups.count, 1)
    }

    /// Both agents hold permissions through the event that *is* the prompt.
    /// Claude Code carries one more, because a question and a plan stop a
    /// session without any permission event firing for them.
    func testBothAgentsHoldPermissionsThroughTheSameEvent() {
        XCTAssertTrue(AgentKind.codex.answerEvents.contains("PermissionRequest"))
        XCTAssertTrue(AgentKind.claudeCode.answerEvents.contains("PermissionRequest"))
        XCTAssertTrue(AgentKind.claudeCode.answerEvents.contains("PreToolUse"))
        XCTAssertFalse(AgentKind.codex.answerEvents.contains("PreToolUse"))
    }

    /// Claude Code writes a registry and transcripts of its own, so a reported
    /// row for one would be a duplicate of a row already on screen.
    func testOnlyAnAgentWithNoRegistryReportsItself() {
        XCTAssertTrue(AgentKind.claudeCode.lifecycleEvents.isEmpty)
        XCTAssertFalse(AgentKind.codex.lifecycleEvents.isEmpty)
    }

    /// An install written before the permission event existed has the switch
    /// on and half the wiring, so it has to read as on and then be repaired.
    func testAnOlderInstallStillReadsAsOn() {
        let older = HookInstall.adding(command: command, to: [:], event: "PreToolUse")
        XCTAssertTrue(HookInstall.isInstalled(agent: .claudeCode, command: command, in: older))

        let repaired = HookInstall.adding(agent: .claudeCode, command: command, to: older)
        XCTAssertTrue(HookInstall.isInstalled(repaired, command: command,
                                              event: "PermissionRequest"))
        XCTAssertTrue(HookInstall.isInstalled(repaired, command: command, event: "PreToolUse"))
    }
}

@MainActor
final class ReportedSessionTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_700_000_000)

    private func report(_ event: String, tool: String? = nil, detail: String? = nil,
                        at offset: TimeInterval = 0) -> SessionReport {
        SessionReport(source: .codex, sessionId: "abc", cwd: "/tmp/perch", event: event,
                      tool: tool, detail: detail, at: now.addingTimeInterval(offset))
    }

    func testASessionAppearsWhenItStarts() throws {
        let store = ReportedSessions()
        store.receive(report("SessionStart"))
        let session = try XCTUnwrap(store.sessions(now: now).first)
        XCTAssertEqual(session.agent, .codex)
        XCTAssertEqual(session.projectName, "perch")
        XCTAssertEqual(session.state, .running)
    }

    func testATurnEndingIsDone() throws {
        let store = ReportedSessions()
        store.receive(report("SessionStart"))
        store.receive(report("Stop", at: 10))
        XCTAssertEqual(try XCTUnwrap(store.sessions(now: now).first).state, .done)
    }

    /// A session that says it has ended is not one that is done; it is one
    /// that is not there.
    func testASessionThatEndsLeavesNoRow() {
        let store = ReportedSessions()
        store.receive(report("SessionStart"))
        store.receive(report("SessionEnd", at: 10))
        XCTAssertTrue(store.sessions(now: now).isEmpty)
    }

    /// A tool call with nothing after it is a slow build until the grace period
    /// runs out, which is the same rule the transcripts get.
    func testAToolCallWithNothingAfterItGoesStalled() throws {
        let store = ReportedSessions()
        store.receive(report("PreToolUse", tool: "shell", detail: "npm test"))

        let running = try XCTUnwrap(store.sessions(now: now).first)
        XCTAssertEqual(running.state, .running)
        XCTAssertEqual(running.activity, "shell")
        XCTAssertEqual(running.detail, "npm test")

        let later = now.addingTimeInterval(TranscriptReader.stallGrace + 1)
        XCTAssertEqual(try XCTUnwrap(store.sessions(now: later).first).state,
                       .blocked(.stalledTool(name: "shell")))
    }

    /// Not every event repeats what a session is running on, and a row that
    /// blanks between two of them flickers.
    func testWhatItIsDoingSurvivesAnEventThatDoesNotSayIt() throws {
        let store = ReportedSessions()
        store.receive(report("PreToolUse", tool: "shell", detail: "npm test"))
        store.receive(report("PostToolUse", at: 1))
        XCTAssertEqual(try XCTUnwrap(store.sessions(now: now).first).detail, "npm test")
    }

    func testATurnEndingClearsWhatItWasDoing() throws {
        let store = ReportedSessions()
        store.receive(report("PreToolUse", tool: "shell", detail: "npm test"))
        store.receive(report("Stop", at: 2))
        let session = try XCTUnwrap(store.sessions(now: now).first)
        XCTAssertNil(session.activity)
        XCTAssertNil(session.detail)
    }

    /// An agent killed rather than closed sends no SessionEnd.
    func testASilentSessionIsEventuallyForgotten() {
        let store = ReportedSessions()
        store.receive(report("Stop"))
        store.expire(now: now.addingTimeInterval(ReportedSessions.forgetAfter - 1))
        XCTAssertEqual(store.sessions(now: now).count, 1)
        store.expire(now: now.addingTimeInterval(ReportedSessions.forgetAfter + 1))
        XCTAssertTrue(store.sessions(now: now).isEmpty)
    }

    func testTurningAnAgentOffTakesItsRowsWithIt() {
        let store = ReportedSessions()
        store.receive(report("SessionStart"))
        store.forget(.claudeCode)
        XCTAssertEqual(store.sessions(now: now).count, 1)
        store.forget(.codex)
        XCTAssertTrue(store.sessions(now: now).isEmpty)
    }

    func testASessionWithNoIdIsNotASession() {
        let store = ReportedSessions()
        store.receive(SessionReport(source: .codex, sessionId: "", cwd: "/tmp/perch",
                                    event: "SessionStart", at: now))
        XCTAssertTrue(store.sessions(now: now).isEmpty)
    }

    /// The hook is gone by the time a row is clicked, so it hands over the
    /// chain above itself instead.
    func testTheChainToClimbIsKept() throws {
        let store = ReportedSessions()
        store.receive(SessionReport(source: .codex, sessionId: "abc", cwd: "/tmp/perch",
                                    event: "SessionStart", ancestors: [42, 7], at: now))
        XCTAssertEqual(try XCTUnwrap(store.sessions(now: now).first).ancestors, [42, 7])
    }
}

final class HookOutputTests: XCTestCase {
    private func body(_ reply: ApprovalReply, _ event: String) -> [String: Any] {
        HookOutput.body(reply, for: event)["hookSpecificOutput"] as? [String: Any] ?? [:]
    }

    /// The documented form is `{"behavior": "allow"}`. Getting this wrong is
    /// silent: the agent rejects the output and prompts as it always did.
    func testAPermissionRequestAnswerIsAVerdictObject() throws {
        let output = body(ApprovalReply(decision: .allow, reason: "Allowed from the island"),
                          "PermissionRequest")
        XCTAssertEqual(output["hookEventName"] as? String, "PermissionRequest")
        let verdict = try XCTUnwrap(output["decision"] as? [String: Any])
        XCTAssertEqual(verdict["behavior"] as? String, "allow")
        // The allow form carries no message, so none is sent.
        XCTAssertNil(verdict["message"])
    }

    func testADenialCarriesTheReasonThatExplainsIt() throws {
        let output = body(ApprovalReply(decision: .deny, reason: "Denied from the island"),
                          "PermissionRequest")
        let verdict = try XCTUnwrap(output["decision"] as? [String: Any])
        XCTAssertEqual(verdict["behavior"] as? String, "deny")
        XCTAssertEqual(verdict["message"] as? String, "Denied from the island")
    }

    /// PreToolUse takes the older shape, and its reason is the only thing a
    /// session reads back -- which is what makes it the way to answer a
    /// question or send a plan back.
    func testPreToolUseKeepsItsOwnShape() {
        let output = body(.answer("Luxon"), "PreToolUse")
        XCTAssertEqual(output["hookEventName"] as? String, "PreToolUse")
        XCTAssertEqual(output["permissionDecision"] as? String, "deny")
        XCTAssertEqual((output["permissionDecisionReason"] as? String)?.contains("Luxon"), true)
        XCTAssertNil(output["decision"])
    }

    func testEveryAnswerSerialises() {
        for event in ["PermissionRequest", "PreToolUse"] {
            XCTAssertNotNil(HookOutput.data(.approvePlan, for: event), event)
            XCTAssertNotNil(HookOutput.data(.revisePlan, for: event), event)
        }
    }
}
