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
        XCTAssertNotNil(installed[AgentKind.codex.permissionEvent])
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
        XCTAssertEqual(try timeout(AgentKind.codex.permissionEvent), HookInstall.hookTimeout)
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

    /// Claude Code's PreToolUse fires for every call, so the mode still has to
    /// be read there. Codex's PermissionRequest is the prompt itself.
    func testOnlyCodexIsTakenAtItsWord() {
        XCTAssertTrue(AgentKind.codex.promptsAreExact)
        XCTAssertFalse(AgentKind.claudeCode.promptsAreExact)
        XCTAssertTrue(AgentKind.claudeCode.lifecycleEvents.isEmpty)
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

@MainActor
final class ExactPromptTests: XCTestCase {
    /// Codex only fires its permission event where a prompt was about to
    /// appear, so no mode of its own can talk Roost out of showing the card.
    func testACodexPromptIsHeldWithoutAskingAboutTheMode() async {
        let center = ApprovalCenter()
        center.permissionMode = { _ in "bypassPermissions" }
        let held = ApprovalRequest(sessionId: "abc", cwd: "/tmp/perch", tool: "shell",
                                   detail: "npm test", source: .codex)
        let answered = Task { await center.handle(held) }
        try? await Task.sleep(for: .milliseconds(30))

        XCTAssertEqual(center.current?.id, held.id)
        center.decide(held.id, .allow)
        let reply = await answered.value
        XCTAssertEqual(reply.decision, .allow)
    }

    func testTheSameCallFromClaudeCodeStillAsksAboutTheMode() async {
        let center = ApprovalCenter()
        center.permissionMode = { _ in "bypassPermissions" }
        let held = ApprovalRequest(sessionId: "s", cwd: "/tmp/perch", tool: "Bash", detail: "ls")
        let reply = await center.handle(held)
        XCTAssertEqual(reply.decision, .ask)
        XCTAssertTrue(center.pending.isEmpty)
    }
}
