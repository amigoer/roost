import XCTest
@testable import RoostCore

final class UsageReadingTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_700_000_000)

    func testBothWindowsAreRead() throws {
        let usage = try XCTUnwrap(Usage.read(statusLine: [
            "rate_limits": [
                "five_hour": ["used_percentage": 62.5, "resets_at": 1_700_003_600.0],
                "seven_day": ["used_percentage": 14.0],
            ],
        ], now: now))
        XCTAssertEqual(usage.fiveHour?.used ?? 0, 0.625, accuracy: 0.0001)
        XCTAssertEqual(usage.sevenDay?.used ?? 0, 0.14, accuracy: 0.0001)
        XCTAssertEqual(usage.fiveHour?.remaining(now: now), 3600)
        XCTAssertNil(usage.sevenDay?.resetsAt)
    }

    /// One build sends seconds since the epoch, another an ISO 8601 string.
    /// Guessing wrong shows a countdown off by decades.
    func testAResetIsReadInEitherShape() {
        XCTAssertEqual(Usage.resetDate(1_700_003_600.0),
                       Date(timeIntervalSince1970: 1_700_003_600))
        XCTAssertEqual(Usage.resetDate("2023-11-14T23:13:20Z"),
                       Date(timeIntervalSince1970: 1_700_003_600))
        XCTAssertNil(Usage.resetDate(nil))
        XCTAssertNil(Usage.resetDate("not a date"))
    }

    /// The block is absent entirely on API billing, and a missing window has to
    /// read as unknown rather than as none left.
    func testNoBlockIsNoFigureRatherThanZero() {
        XCTAssertNil(Usage.read(statusLine: [:]))
        XCTAssertNil(Usage.read(statusLine: ["rate_limits": [:]]))
    }

    func testOneWindowAloneStillCounts() throws {
        let usage = try XCTUnwrap(Usage.read(statusLine: [
            "rate_limits": ["five_hour": ["used_percentage": 5.0]],
        ], now: now))
        XCTAssertNotNil(usage.fiveHour)
        XCTAssertNil(usage.sevenDay)
    }

    func testAFigureIsClampedToItsWindow() {
        XCTAssertEqual(UsageWindow(used: 1.4).used, 1)
        XCTAssertEqual(UsageWindow(used: -2).used, 0)
    }

    /// Nothing writes a status line once the last session closes, so a figure
    /// left on screen after that describes a window that has moved on.
    func testAStaleFigureStopsCounting() {
        let usage = Usage(fiveHour: UsageWindow(used: 0.5), sevenDay: nil, reportedAt: now)
        XCTAssertTrue(usage.isFresh(now: now.addingTimeInterval(60)))
        XCTAssertFalse(usage.isFresh(now: now.addingTimeInterval(Usage.freshness + 1)))
    }

    func testAResetAlreadyPastCountsAsNow() {
        let window = UsageWindow(used: 0.9, resetsAt: now.addingTimeInterval(-500))
        XCTAssertEqual(window.remaining(now: now), 0)
    }
}

final class StatusLineInstallTests: XCTestCase {
    private let helper = "/Applications/Roost.app/Contents/MacOS/roost-hook"

    func testItInstallsWhereThereWasNothing() throws {
        let settings = StatusLineInstall.adding(command: helper, to: [:])
        XCTAssertTrue(StatusLineInstall.isInstalled(settings, command: helper))
        let command = try XCTUnwrap((settings["statusLine"] as? [String: Any])?["command"] as? String)
        XCTAssertTrue(command.contains(helper))
        XCTAssertTrue(command.contains(StatusLineInstall.flag))
        XCTAssertFalse(command.contains(StatusLineInstall.wrapFlag))
    }

    /// The whole point: someone else's status line keeps running.
    func testAnExistingStatusLineIsCarriedAlong() throws {
        let existing = ["type": "command", "command": "~/.claude/statusline.sh", "padding": 0] as [String: Any]
        let settings = StatusLineInstall.adding(command: helper, to: ["statusLine": existing])
        let command = try XCTUnwrap((settings["statusLine"] as? [String: Any])?["command"] as? String)

        let wrapped = try XCTUnwrap(StatusLineInstall.wrapped(in: command))
        XCTAssertEqual(wrapped["command"] as? String, "~/.claude/statusline.sh")
        // Everything it carried comes back, not just the command.
        XCTAssertEqual(wrapped["padding"] as? Int, 0)
    }

    func testRemovingPutsTheOriginalBackExactly() throws {
        let existing = ["type": "command", "command": "~/.claude/statusline.sh"] as [String: Any]
        let installed = StatusLineInstall.adding(command: helper, to: ["statusLine": existing])
        let removed = StatusLineInstall.removing(command: helper, from: installed)

        let restored = try XCTUnwrap(removed["statusLine"] as? [String: Any])
        XCTAssertEqual(restored["command"] as? String, "~/.claude/statusline.sh")
        XCTAssertFalse(StatusLineInstall.isInstalled(removed, command: helper))
    }

    func testRemovingLeavesNoScaffoldingWhenThereWasNone() {
        let installed = StatusLineInstall.adding(command: helper, to: [:])
        XCTAssertTrue(StatusLineInstall.removing(command: helper, from: installed).isEmpty)
    }

    /// Installing twice must not wrap Roost in Roost.
    func testInstallingTwiceChangesNothing() {
        let once = StatusLineInstall.adding(command: helper, to: [:])
        XCTAssertEqual(StatusLineInstall.adding(command: helper, to: once)["statusLine"] as? [String: String],
                       once["statusLine"] as? [String: String])
    }

    /// Somebody else's status line is not ours to take out.
    func testAStatusLineNobodyHereWroteIsLeftAlone() {
        let theirs: [String: Any] = ["statusLine": ["type": "command", "command": "/opt/other-tool"]]
        let after = StatusLineInstall.removing(command: helper, from: theirs)
        XCTAssertEqual((after["statusLine"] as? [String: Any])?["command"] as? String, "/opt/other-tool")
        XCTAssertFalse(StatusLineInstall.isInstalled(theirs, command: helper))
    }

    func testTheShimKnowsWhatToRun() throws {
        let existing = ["type": "command", "command": "printf hello"] as [String: Any]
        let command = StatusLineInstall.command(helper: helper, wrapping: existing)
        let argument = try XCTUnwrap(command.split(separator: " ").last.map(String.init))
        XCTAssertEqual(StatusLineInstall.wrappedCommand(in: argument), "printf hello")
    }
}

final class HookMessageTests: XCTestCase {
    func testAUsageReportSurvivesTheWire() throws {
        let usage = Usage(fiveHour: UsageWindow(used: 0.5), sevenDay: nil)
        let line = try JSONEncoder.wire.encode(HookMessage.usage(usage))
        guard case .usage(let decoded) = try XCTUnwrap(HookMessage.decode(line)) else {
            return XCTFail("expected a usage report")
        }
        XCTAssertEqual(decoded.fiveHour?.used, 0.5)
    }

    /// A bundle can be left holding an older helper, and one already running
    /// has a session stopped behind it.
    func testABareRequestFromAnOlderHelperStillArrives() throws {
        let request = ApprovalRequest(sessionId: "s", cwd: "/tmp/perch", tool: "Bash", detail: "ls")
        let line = try JSONEncoder.wire.encode(request)
        guard case .approval(let decoded) = try XCTUnwrap(HookMessage.decode(line)) else {
            return XCTFail("expected a held call")
        }
        XCTAssertEqual(decoded.tool, "Bash")
    }

    func testNonsenseIsNotAMessage() {
        XCTAssertNil(HookMessage.decode(Data("{\"nope\":1}".utf8)))
    }
}
