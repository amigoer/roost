import XCTest
@testable import RoostCore

final class ApprovalGateTests: XCTestCase {
    /// The gate holds no policy any more. `PermissionRequest` runs where a
    /// prompt is about to appear and nowhere else, so there is nothing left to
    /// work out about which calls would have been asked about -- only the two
    /// that stop a session without being permissions at all.
    func testOnlyAQuestionAndAPlanAreClaimedFromPreToolUse() {
        XCTAssertEqual(ApprovalGate.asks, ["AskUserQuestion", "ExitPlanMode"])
        XCTAssertNil(ApprovalGate.ask(tool: "Bash", input: ["command": "ls"]))
        XCTAssertNil(ApprovalGate.ask(tool: "Edit", input: ["file_path": "/x/a.swift"]))
    }

    func testAQuestionAndAPlanArriveAsTheirOwnKinds() throws {
        let question = try XCTUnwrap(ApprovalGate.ask(tool: "AskUserQuestion", input: [
            "questions": [["question": "Which one?", "options": [["label": "a"], ["label": "b"]]]],
        ]))
        guard case .question = question else { return XCTFail("expected a question") }

        let plan = try XCTUnwrap(ApprovalGate.ask(tool: "ExitPlanMode",
                                                  input: ["plan": "## Approach"]))
        guard case .plan = plan else { return XCTFail("expected a plan") }
    }

    /// One that cannot be put on a card in full is left to prompt where it did.
    func testAnUnanswerableAskIsNotClaimed() {
        XCTAssertNil(ApprovalGate.ask(tool: "ExitPlanMode", input: ["plan": "  "]))
        XCTAssertNil(ApprovalGate.ask(tool: "AskUserQuestion", input: ["questions": []]))
    }

    func testTheRowIsToldWhatIsBeingAsked() throws {
        let plan = try XCTUnwrap(ApprovalGate.ask(tool: "ExitPlanMode",
                                                  input: ["plan": "## Approach\n- do it"]))
        XCTAssertEqual(ApprovalGate.summary(of: plan), "Approach")
        // A permission says what it is running instead, which the row already
        // reads off the tool input.
        XCTAssertNil(ApprovalGate.summary(of: .permission))
    }
}

final class HeldCallTests: XCTestCase {
    private func session(id: String = "s", startedAt: Date = Date(),
                         state: SessionState = .running) -> Session {
        Session(id: id, pid: 1, name: "perch-9b", cwd: "/x/roost", entrypoint: "claude-desktop",
                startedAt: startedAt, state: state, stateSince: startedAt,
                activity: "Bash", detail: "swift build", lastActivityAt: startedAt)
    }

    private func request(agent: String? = nil, receivedAt: Date = Date()) -> ApprovalRequest {
        ApprovalRequest(sessionId: "s", cwd: "/x/roost", tool: "Bash",
                        detail: "du -sh ~/.ollama", agent: agent, receivedAt: receivedAt)
    }

    func testACallFromTheMainThreadIsAPermissionPrompt() {
        XCTAssertEqual(request().blockReason, .permissionPrompt(tool: "Bash"))
    }

    /// The hook is the only thing that knows a sub-agent made the call, and
    /// naming it is what sends you to the right part of the conversation.
    func testACallFromASubAgentNamesTheAgent() {
        XCTAssertEqual(request(agent: "Explore").blockReason, .agentNeedsInput(label: "Explore"))
    }

    /// The transcript still reads as a tool in flight while the card is up, so
    /// without this the row says "running Bash" under a card asking whether
    /// that Bash may run.
    func testAHeldSessionReadsAsBlocked() {
        let held = session().held(by: request())
        XCTAssertEqual(held.state, .blocked(.permissionPrompt(tool: "Bash")))
        XCTAssertEqual(held.detail, "du -sh ~/.ollama")
    }

    /// Elapsed counts from the card, not from whenever the tool call started.
    func testItCountsFromTheCard() {
        let card = request(receivedAt: Date().addingTimeInterval(-30))
        let held = session(startedAt: Date().addingTimeInterval(-600)).held(by: card)
        XCTAssertEqual(held.stateSince, card.receivedAt)
        XCTAssertEqual(held.blockedFor, 30, accuracy: 1)
    }

    /// A session waiting on a card is the loudest thing listed, and sorts like
    /// it even though the scan that produced it saw only a running tool.
    func testAHeldSessionSortsToTheTop() {
        let newer = session(id: "newer", startedAt: Date())
        let held = session(id: "s", startedAt: Date().addingTimeInterval(-600)).held(by: request())
        XCTAssertEqual(Session.ordered([newer, held]).map(\.id), ["s", "newer"])
    }

    /// Hook and app ship in one bundle, but a payload written by an older hook
    /// must not fail to decode: the field it lacks only means "not an agent".
    func testAPayloadWithoutAnAgentStillDecodes() throws {
        let json = #"{"id":"1","sessionId":"s","cwd":"/x/roost","tool":"Bash","receivedAt":0}"#
        let decoded = try JSONDecoder().decode(ApprovalRequest.self, from: Data(json.utf8))
        XCTAssertNil(decoded.agent)
        XCTAssertEqual(decoded.blockReason, .permissionPrompt(tool: "Bash"))
    }
}

final class ApprovalClientTests: XCTestCase {
    /// The property everything else rests on: with nothing listening, the hook
    /// gets no answer and the session prompts the way it always did.
    func testNoServerMeansNoAnswer() {
        let request = ApprovalRequest(sessionId: "s", cwd: "/tmp", tool: "Bash", detail: "ls")
        let reply = ApprovalClient.ask(request,
                                       path: "/tmp/roost-tests-nothing-here.sock",
                                       timeout: 1)
        XCTAssertNil(reply)
    }
}

final class HookInstallTests: XCTestCase {
    private let command = "/Applications/Roost.app/Contents/MacOS/roost-hook"

    func testAddingIsIdempotent() {
        let once = HookInstall.adding(command: command, to: [:])
        let twice = HookInstall.adding(command: command, to: once)
        let groups = (twice["hooks"] as? [String: Any])?["PreToolUse"] as? [[String: Any]]
        XCTAssertEqual(groups?.count, 1)
        XCTAssertTrue(HookInstall.isInstalled(twice, command: command))
    }

    func testOtherHooksAreLeftAlone() {
        let existing: [String: Any] = [
            "model": "opus",
            "hooks": ["PreToolUse": [["matcher": "Bash",
                                      "hooks": [["type": "command", "command": "/usr/bin/logger"]]]],
                      "PostToolUse": [["matcher": "*", "hooks": [["type": "command", "command": "fmt"]]]]],
        ]
        let added = HookInstall.adding(command: command, to: existing)
        let removed = HookInstall.removing(command: command, from: added)

        XCTAssertEqual((added["hooks"] as? [String: Any])?["PreToolUse"] as? [[String: Any]] != nil, true)
        XCTAssertEqual(((removed["hooks"] as? [String: Any])?["PreToolUse"] as? [[String: Any]])?.count, 1)
        XCTAssertNotNil((removed["hooks"] as? [String: Any])?["PostToolUse"])
        XCTAssertEqual(removed["model"] as? String, "opus")
        XCTAssertFalse(HookInstall.isInstalled(removed, command: command))
    }

    /// Removing the last one should not leave an empty `hooks` object behind.
    func testRemovingCleansUpAfterItself() {
        let added = HookInstall.adding(command: command, to: [:])
        XCTAssertTrue(HookInstall.removing(command: command, from: added).isEmpty)
    }
}

final class ApprovalGeometryTests: XCTestCase {
    private let notch = CGSize(width: 190, height: 38)
    private let width = IslandGeometry.expandedWidth

    private var buttonMiddle: CGFloat {
        IslandGeometry.rowsTopInset(notch: notch) + IslandGeometry.Held.permissionHeight / 2
    }

    func testAllowIsTheRightmostButton() {
        let x = width - IslandGeometry.Approval.trailingInset - IslandGeometry.Approval.buttonWidth / 2
        XCTAssertEqual(IslandGeometry.approvalHit(offsetFromTop: buttonMiddle, offsetFromLeft: x,
                                                  notch: notch, islandWidth: width), .allow)
    }

    func testDenySitsLeftOfAllowWithAGapBetween() {
        let allowStart = width - IslandGeometry.Approval.trailingInset - IslandGeometry.Approval.buttonWidth
        let denyMiddle = allowStart - IslandGeometry.Approval.gap - IslandGeometry.Approval.buttonWidth / 2
        XCTAssertEqual(IslandGeometry.approvalHit(offsetFromTop: buttonMiddle, offsetFromLeft: denyMiddle,
                                                  notch: notch, islandWidth: width), .deny)
        // The gap must answer nothing rather than answer wrongly.
        let gapMiddle = allowStart - IslandGeometry.Approval.gap / 2
        XCTAssertNil(IslandGeometry.approvalHit(offsetFromTop: buttonMiddle, offsetFromLeft: gapMiddle,
                                                notch: notch, islandWidth: width))
    }

    func testTextSideOfTheCardAnswersNothing() {
        XCTAssertNil(IslandGeometry.approvalHit(offsetFromTop: buttonMiddle, offsetFromLeft: 40,
                                                notch: notch, islandWidth: width))
    }

    func testAboveAndBelowTheButtonsAnswersNothing() {
        let x = width - IslandGeometry.Approval.trailingInset - IslandGeometry.Approval.buttonWidth / 2
        let cardTop = IslandGeometry.rowsTopInset(notch: notch)
        XCTAssertNil(IslandGeometry.approvalHit(offsetFromTop: cardTop + 2, offsetFromLeft: x,
                                                notch: notch, islandWidth: width))
        XCTAssertNil(IslandGeometry.approvalHit(offsetFromTop: cardTop + IslandGeometry.Held.permissionHeight - 2,
                                                offsetFromLeft: x, notch: notch, islandWidth: width))
    }

    /// The card pushes the list down; a click meant for the first row must not
    /// land on the card, and vice versa.
    func testRowsShiftBelowTheCard() {
        let card = IslandGeometry.Held.height(.permission)
        let firstRow = IslandGeometry.rowsTopInset(notch: notch, heldHeight: card) + 4
        XCTAssertEqual(IslandGeometry.rowIndex(atOffsetFromTop: firstRow, notch: notch,
                                               rowCount: 3, heldHeight: card), 0)
        XCTAssertNil(IslandGeometry.approvalHit(offsetFromTop: firstRow, offsetFromLeft: width - 40,
                                                notch: notch, islandWidth: width))
    }
}

@MainActor
final class ApprovalCenterTests: XCTestCase {
    private func request(_ tool: String = "Bash") -> ApprovalRequest {
        ApprovalRequest(sessionId: "s", cwd: "/x/perch", tool: tool, detail: "ls")
    }

    private func waitForCard(_ center: ApprovalCenter) async {
        while center.pending.isEmpty { await Task.yield() }
    }

    func testAnsweringReleasesTheHeldCall() async {
        let center = ApprovalCenter()
        let held = request()
        let reply = Task { await center.handle(held) }
        await waitForCard(center)

        center.decide(held.id, .allow)

        let answer = await reply.value
        XCTAssertEqual(answer.decision, .allow)
        XCTAssertTrue(center.pending.isEmpty)
    }

    func testDenyingReleasesItToo() async {
        let center = ApprovalCenter()
        let held = request()
        let reply = Task { await center.handle(held) }
        await waitForCard(center)

        center.decide(held.id, .deny)

        let answer = await reply.value
        XCTAssertEqual(answer.decision, .deny)
    }

    /// Nobody answered: the call goes back to the session's own prompt rather
    /// than sitting on a card forever.
    func testExpiryHandsTheCallBack() async {
        let center = ApprovalCenter()
        let stale = ApprovalRequest(sessionId: "s", cwd: "/x", tool: "Bash", detail: "ls",
                                    receivedAt: Date().addingTimeInterval(-ApprovalSocket.timeout - 1))
        let reply = Task { await center.handle(stale) }
        await waitForCard(center)

        center.expireStale()

        let answer = await reply.value
        XCTAssertEqual(answer.decision, .ask)
        XCTAssertTrue(center.pending.isEmpty)
    }

    /// Everything that arrives is held. The helper only sends calls an agent
    /// was really about to prompt about, so a card here is a prompt there --
    /// which is what the permission event bought and what nothing in this
    /// class has to work out any more.
    func testEveryHeldCallBecomesACard() async {
        let center = ApprovalCenter()
        let held = request("Edit")
        let reply = Task { await center.handle(held) }
        await waitForCard(center)

        XCTAssertEqual(center.current?.id, held.id)
        center.decide(held.id, .allow)
        let answer = await reply.value
        XCTAssertEqual(answer.decision, .allow)
    }
}

final class UpdateCheckTests: XCTestCase {
    func testOrdersByComponent() {
        XCTAssertTrue(UpdateCheck.isNewer("0.1.2", than: "0.1.1"))
        XCTAssertTrue(UpdateCheck.isNewer("0.2.0", than: "0.1.9"))
        XCTAssertTrue(UpdateCheck.isNewer("1.0.0", than: "0.9.9"))
        XCTAssertFalse(UpdateCheck.isNewer("0.1.1", than: "0.1.1"))
        XCTAssertFalse(UpdateCheck.isNewer("0.1.0", than: "0.1.1"))
    }

    /// 0.1.10 is newer than 0.1.9, which string comparison gets backwards.
    func testDoubleDigitsAreNumbers() {
        XCTAssertTrue(UpdateCheck.isNewer("0.1.10", than: "0.1.9"))
        XCTAssertFalse(UpdateCheck.isNewer("0.1.9", than: "0.1.10"))
    }

    func testShorterVersionsPadWithZeros() {
        XCTAssertTrue(UpdateCheck.isNewer("0.2", than: "0.1.9"))
        XCTAssertFalse(UpdateCheck.isNewer("0.1", than: "0.1.0"))
    }

    /// A reply that makes no sense must never look like an update.
    func testGarbageIsNotAnUpdate() {
        XCTAssertFalse(UpdateCheck.isNewer("", than: "0.1.1"))
        XCTAssertFalse(UpdateCheck.isNewer("latest", than: "0.1.1"))
    }

    func testReadsTheTagAndPage() throws {
        let body = """
        {"tag_name":"v0.1.2","html_url":"https://github.com/amigoer/roost/releases/tag/v0.1.2",
         "draft":false,"prerelease":false}
        """
        let release = try XCTUnwrap(UpdateCheck.release(from: Data(body.utf8)))
        XCTAssertEqual(release.version, "0.1.2")
        XCTAssertEqual(release.page.lastPathComponent, "v0.1.2")
    }

    func testDraftsAndPrereleasesAreIgnored() {
        let draft = #"{"tag_name":"v9.9.9","html_url":"https://x.test","draft":true}"#
        let early = #"{"tag_name":"v9.9.9","html_url":"https://x.test","prerelease":true}"#
        XCTAssertNil(UpdateCheck.release(from: Data(draft.utf8)))
        XCTAssertNil(UpdateCheck.release(from: Data(early.utf8)))
    }
}

final class MenuHitTests: XCTestCase {
    private let notch = CGSize(width: 190, height: 38)
    private let width = IslandGeometry.expandedWidth

    func testTheMenuButtonSitsInTheHeaderCorner() {
        let x = width - IslandGeometry.Menu.trailingInset - IslandGeometry.Menu.buttonSize / 2
        XCTAssertTrue(IslandGeometry.menuHit(offsetFromTop: notch.height / 2, offsetFromLeft: x,
                                             notch: notch, islandWidth: width))
    }

    func testBelowTheHeaderIsNotTheMenu() {
        let x = width - IslandGeometry.Menu.trailingInset - IslandGeometry.Menu.buttonSize / 2
        XCTAssertFalse(IslandGeometry.menuHit(offsetFromTop: notch.height + 10, offsetFromLeft: x,
                                              notch: notch, islandWidth: width))
    }

    func testTheRestOfTheHeaderIsNotTheMenu() {
        XCTAssertFalse(IslandGeometry.menuHit(offsetFromTop: notch.height / 2, offsetFromLeft: 40,
                                              notch: notch, islandWidth: width))
    }
}

final class RegistryDeduplicationTests: XCTestCase {
    private func entry(_ id: String, pid: pid_t, startedAt: Date) -> RegistryEntry {
        RegistryEntry(pid: pid, sessionId: id, cwd: "/x/perch", name: nil,
                      startedAt: startedAt, entrypoint: "claude-desktop")
    }

    /// Two processes against one transcript is still one conversation, and the
    /// one that has been running is the one to keep.
    func testOneRowPerSessionRegardlessOfProcesses() {
        let old = Date(timeIntervalSince1970: 1_000)
        let new = Date(timeIntervalSince1970: 2_000)
        let entries = [entry("a", pid: 10477, startedAt: new),
                       entry("a", pid: 58497, startedAt: old),
                       entry("b", pid: 99648, startedAt: new)]

        let result = SessionRegistry.deduplicated(entries)

        XCTAssertEqual(result.map(\.sessionId), ["a", "b"])
        XCTAssertEqual(result.first?.pid, 58497)
    }
}

final class SessionLinkTests: XCTestCase {
    private let cli = "b2d3426a-ead4-4837-b918-e6cb3ce5446b"
    private let record = "local_3833ff2d-7f71-4390-ad52-e436bb174137"

    /// The app puts `local_` back on whatever it is given and focuses the
    /// record it finds, so its own id -- prefix removed -- lands on the
    /// original conversation and imports nothing.
    func testAKnownSessionOpensByTheAppsOwnId() {
        XCTAssertEqual(SessionLink.resumeParameter(desktopRecordId: record, cliSessionId: cli,
                                                   entrypoint: "claude-desktop"),
                       "3833ff2d-7f71-4390-ad52-e436bb174137")
    }

    /// A terminal session has no record anywhere, so the CLI id is right: the
    /// import is how it reaches the desktop app at all.
    func testATerminalSessionOpensByCliId() {
        XCTAssertEqual(SessionLink.resumeParameter(desktopRecordId: nil, cliSessionId: cli,
                                                   entrypoint: "cli"),
                       cli)
    }

    /// The case that duplicated: the app started this one and its record is
    /// moments from being written. The CLI id would import a copy beside it.
    func testABrandNewDesktopSessionWaitsForItsRecord() {
        XCTAssertNil(SessionLink.resumeParameter(desktopRecordId: nil, cliSessionId: cli,
                                                 entrypoint: "claude-desktop"))
    }

    func testTheUrlCarriesTheParameter() throws {
        let url = try XCTUnwrap(SessionLink.resume(session: cli))
        XCTAssertEqual(url.absoluteString, "claude://resume?session=\(cli)")
    }

    func testNothingToOpenIsNoLink() {
        XCTAssertNil(SessionLink.resume(session: ""))
        XCTAssertNil(SessionLink.resumeParameter(desktopRecordId: nil, cliSessionId: "",
                                                 entrypoint: "cli"))
    }
}

/// Giving a held call back to the session it came from.
///
/// Holding a call is also taking it away: while the island has it, the agent's
/// own prompt does not appear. Roost stands in for that prompt rather than
/// owning it, so there has to be a way out that leaves the session exactly as
/// it would have been.
@MainActor
final class HandBackTests: XCTestCase {
    private func request(_ kind: HeldKind) -> ApprovalRequest {
        ApprovalRequest(sessionId: "s1", cwd: "/tmp/roost", tool: "AskUserQuestion",
                        detail: nil, kind: kind)
    }

    private let question = HeldQuestion(
        prompt: "which one?", header: "Approach",
        options: [.init(label: "A"), .init(label: "B")])

    func testHandingBackLeavesTheSessionToPromptItself() async {
        let centre = ApprovalCenter()
        let held = request(.question(question))
        async let reply = centre.handle(held)
        while centre.current == nil { await Task.yield() }
        centre.handBack(held.id)
        let decision = await reply
        // `ask` is the one decision the hook prints nothing for, which is what
        // makes the session prompt the way it always did.
        XCTAssertEqual(decision.decision, ApprovalDecision.ask)
    }

    func testHandingBackClearsTheCard() async {
        let centre = ApprovalCenter()
        let held = request(.question(question))
        async let reply = centre.handle(held)
        while centre.current == nil { await Task.yield() }
        centre.handBack(held.id)
        _ = await reply
        XCTAssertNil(centre.current)
        XCTAssertTrue(centre.pending.isEmpty)
    }

    /// A hand-back must not read as an answer: nothing was chosen.
    func testHandingBackIsNotAnAnswer() async {
        let centre = ApprovalCenter()
        let held = request(.question(question))
        async let reply = centre.handle(held)
        while centre.current == nil { await Task.yield() }
        centre.handBack(held.id)
        let decision = await reply
        XCTAssertNil(decision.reason)
        XCTAssertNotEqual(decision.decision, ApprovalDecision.deny)
    }

    /// The same door the timeout already uses, so both leave the session in the
    /// one state it knows how to recover from.
    func testATimeoutHandsBackTheSameWay() async {
        let centre = ApprovalCenter()
        let held = request(.question(question))
        async let reply = centre.handle(held)
        while centre.current == nil { await Task.yield() }
        centre.expireStale(now: Date().addingTimeInterval(ApprovalSocket.timeout + 1))
        let decision = await reply
        XCTAssertEqual(decision.decision, ApprovalDecision.ask)
    }
}
