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
