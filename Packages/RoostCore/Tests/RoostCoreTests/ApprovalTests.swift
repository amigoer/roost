import XCTest
@testable import RoostCore

final class ApprovalGateTests: XCTestCase {
    func testReadOnlyToolsNeverReachTheApp() {
        XCTAssertFalse(ApprovalGate.mayPrompt(tool: "Read"))
        XCTAssertFalse(ApprovalGate.mayPrompt(tool: "Grep"))
        XCTAssertTrue(ApprovalGate.mayPrompt(tool: "Bash"))
        XCTAssertTrue(ApprovalGate.mayPrompt(tool: "mcp__github__create_pr"))
    }

    func testAcceptEditsHasAlreadyAnsweredForEdits() {
        XCTAssertFalse(ApprovalGate.shouldAsk(tool: "Edit", permissionMode: "acceptEdits"))
        XCTAssertTrue(ApprovalGate.shouldAsk(tool: "Bash", permissionMode: "acceptEdits"))
    }

    func testBypassAsksForNothing() {
        XCTAssertFalse(ApprovalGate.shouldAsk(tool: "Bash", permissionMode: "bypassPermissions"))
        XCTAssertFalse(ApprovalGate.shouldAsk(tool: "Write", permissionMode: "plan"))
    }

    /// An unknown mode is the strict case: better a card than a silent run.
    func testUnknownModeAsks() {
        XCTAssertTrue(ApprovalGate.shouldAsk(tool: "Write", permissionMode: nil))
        XCTAssertTrue(ApprovalGate.shouldAsk(tool: "Write", permissionMode: "default"))
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
        IslandGeometry.rowsTopInset(notch: notch) + IslandGeometry.Approval.height / 2
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
        XCTAssertNil(IslandGeometry.approvalHit(offsetFromTop: cardTop + IslandGeometry.Approval.height - 2,
                                                offsetFromLeft: x, notch: notch, islandWidth: width))
    }

    /// The card pushes the list down; a click meant for the first row must not
    /// land on the card, and vice versa.
    func testRowsShiftBelowTheCard() {
        let firstRow = IslandGeometry.rowsTopInset(notch: notch, hasApproval: true) + 4
        XCTAssertEqual(IslandGeometry.rowIndex(atOffsetFromTop: firstRow, notch: notch,
                                               rowCount: 3, hasApproval: true), 0)
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

    func testACallThatWouldNotPromptNeverBecomesACard() async {
        let center = ApprovalCenter()
        center.permissionMode = { _ in "acceptEdits" }

        let answer = await center.handle(request("Edit"))

        XCTAssertEqual(answer.decision, .ask)
        XCTAssertTrue(center.pending.isEmpty)
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

final class SessionLinkTests: XCTestCase {
    /// The id that works is the CLI session id, not the desktop app's own
    /// `local_` one: handing the resume route a local id gets "missing or
    /// invalid session" and nothing else.
    func testResumeCarriesTheCliSessionId() throws {
        let url = try XCTUnwrap(SessionLink.resume(cliSessionId: "b2d3426a-ead4-4837-b918-e6cb3ce5446b"))
        XCTAssertEqual(url.absoluteString,
                       "claude://resume?session=b2d3426a-ead4-4837-b918-e6cb3ce5446b")
    }

    func testNoIdIsNoLink() {
        XCTAssertNil(SessionLink.resume(cliSessionId: ""))
    }
}

final class ResumeSafetyTests: XCTestCase {
    /// A terminal session is not in the desktop app at all, so importing it is
    /// the whole point rather than a duplicate.
    func testATerminalSessionIsSafeToResume() {
        XCTAssertTrue(SessionLink.resumeIsSafe(entrypoint: "cli", knownToDesktop: false,
                                               hasImportedCopy: false))
    }

    /// The app dedupes on `local_<cli id>`, so the second resume finds the
    /// first one's import and adds nothing.
    func testAnAlreadyImportedSessionIsSafeToResume() {
        XCTAssertTrue(SessionLink.resumeIsSafe(entrypoint: "claude-desktop", knownToDesktop: true,
                                               hasImportedCopy: true))
    }

    /// The app started this one under an id of its own; the import would land
    /// beside it.
    func testASessionTheAppStartedIsNotSafeToResume() {
        XCTAssertFalse(SessionLink.resumeIsSafe(entrypoint: "claude-desktop", knownToDesktop: true,
                                                hasImportedCopy: false))
    }

    /// The case that shipped broken: a conversation started seconds ago is not
    /// in the last scan of the store, so the scan says "unknown" and the
    /// entrypoint is the only thing that knows better.
    func testABrandNewDesktopSessionIsNotSafeToResume() {
        XCTAssertFalse(SessionLink.resumeIsSafe(entrypoint: "claude-desktop", knownToDesktop: false,
                                                hasImportedCopy: false))
    }
}
