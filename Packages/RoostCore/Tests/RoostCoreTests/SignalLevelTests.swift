import XCTest
@testable import RoostCore

final class SignalLevelTests: XCTestCase {
    func testNoSessionsIsDormant() {
        XCTAssertEqual(SignalLevel.aggregate([SessionState]()), .dormant)
    }

    func testBlockedWinsOverEverything() {
        let states: [SessionState] = [.running, .done, .blocked(.question), .running]
        XCTAssertEqual(SignalLevel.aggregate(states), .blocked)
    }

    func testRunningOutranksDone() {
        XCTAssertEqual(SignalLevel.aggregate([.done, .running, .done]), .running)
    }

    func testAllDoneStaysQuietest() {
        XCTAssertEqual(SignalLevel.aggregate([.done, .done]), .done)
    }

    func testDoneIsQuieterThanRunning() {
        XCTAssertLessThan(SignalLevel.done, SignalLevel.running)
        XCTAssertLessThan(SignalLevel.running, SignalLevel.blocked)
    }
}

final class BlockReasonTests: XCTestCase {
    func testHumanOnlyReasonsNeedNoGracePeriod() {
        XCTAssertTrue(BlockReason.question.isImmediate)
        XCTAssertTrue(BlockReason.planApproval.isImmediate)
        XCTAssertTrue(BlockReason.permissionPrompt(tool: "Bash").isImmediate)
        XCTAssertTrue(BlockReason.agentNeedsInput(label: nil).isImmediate)
    }

    func testAStalledToolStillNeedsAGracePeriod() {
        // A dangling Bash may just be a slow build, so it must not fire instantly.
        XCTAssertFalse(BlockReason.stalledTool(name: "Bash").isImmediate)
    }
}

final class EscalationTierTests: XCTestCase {
    func testTierBoundaries() {
        XCTAssertEqual(EscalationTier(blockedFor: 0), .calm)
        XCTAssertEqual(EscalationTier(blockedFor: 59), .calm)
        XCTAssertEqual(EscalationTier(blockedFor: 60), .elevated)
        XCTAssertEqual(EscalationTier(blockedFor: 299), .elevated)
        XCTAssertEqual(EscalationTier(blockedFor: 300), .peek)
        XCTAssertEqual(EscalationTier(blockedFor: 8_000), .peek)
    }
}
