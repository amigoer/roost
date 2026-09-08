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

final class UsageAPIReadingTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_700_000_000)

    /// The reply as the endpoint actually sends it, obfuscated null keys and
    /// all: they are what a new window would arrive as if `limits` were not
    /// read instead, and the point of this fixture is that they stay unread.
    private let reply = Data("""
    {"five_hour":{"utilization":12.0,"resets_at":"2026-09-08T15:39:59.816725+00:00",
     "limit_dollars":null,"used_dollars":null,"remaining_dollars":null,"locked_reason":null},
     "seven_day":{"utilization":76.0,"resets_at":"2026-09-10T14:59:59.816748+00:00",
     "limit_dollars":null,"used_dollars":null,"remaining_dollars":null,"locked_reason":null},
     "seven_day_opus":null,"tangelo":null,"iguana_necktie":null,"nimbus_quill":
     {"utilization":0.0,"resets_at":null,"locked_reason":null},
     "extra_usage":{"is_enabled":false,"utilization":null},
     "limits":[
       {"kind":"session","group":"session","percent":12,"severity":"normal",
        "resets_at":"2026-09-08T15:39:59.816725+00:00","scope":null,"is_active":false},
       {"kind":"weekly_all","group":"weekly","percent":76,"severity":"warning",
        "resets_at":"2026-09-10T14:59:59.816748+00:00","scope":null,"is_active":true},
       {"kind":"weekly_scoped","group":"weekly","percent":52,"severity":"normal",
        "resets_at":"2026-09-10T14:59:59.816968+00:00",
        "scope":{"model":{"id":null,"display_name":"Fable"},"surface":null},"is_active":false}],
     "spend":{"percent":0,"enabled":false},"member_dashboard_available":false}
    """.utf8)

    func testTheTwoWindowsComeOffTheLimitsArray() throws {
        let usage = try XCTUnwrap(UsageAPI.usage(from: reply, now: now))
        XCTAssertEqual(usage.fiveHour?.used ?? 0, 0.12, accuracy: 0.0001)
        XCTAssertEqual(usage.sevenDay?.used ?? 0, 0.76, accuracy: 0.0001)
        XCTAssertEqual(usage.source, .api)
    }

    /// The figures arrive as integers where a status line sends fractions.
    func testAWholeNumberPercentIsStillAFraction() throws {
        let usage = try XCTUnwrap(UsageAPI.usage(from: reply, now: now))
        XCTAssertNotNil(usage.fiveHour)
        XCTAssertEqual(usage.fiveHour?.used ?? 0, 0.12, accuracy: 0.0001)
    }

    func testAResetTimeIsReadFromTheEntry() throws {
        let usage = try XCTUnwrap(UsageAPI.usage(from: reply, now: now))
        let resets = try XCTUnwrap(usage.fiveHour?.resetsAt)
        XCTAssertEqual(resets.timeIntervalSince1970,
                       Date(timeIntervalSince1970: 1_788_881_999.816725).timeIntervalSince1970,
                       accuracy: 1)
    }

    /// A per-model weekly explains a seven-day figure and never replaces it.
    func testAScopedWindowKeepsTheNameItIsShownUnder() throws {
        let usage = try XCTUnwrap(UsageAPI.usage(from: reply, now: now))
        XCTAssertEqual(usage.scoped.count, 1)
        XCTAssertEqual(usage.scoped.first?.label, "Fable")
        XCTAssertEqual(usage.scoped.first?.window.used ?? 0, 0.52, accuracy: 0.0001)
    }

    /// A bar labelled nothing explains nothing.
    func testAScopeWithNoNameIsDropped() throws {
        let nameless = Data("""
        {"limits":[{"kind":"weekly_all","percent":10},
                   {"kind":"weekly_scoped","percent":30,"scope":{"surface":null}}]}
        """.utf8)
        let usage = try XCTUnwrap(UsageAPI.usage(from: nameless, now: now))
        XCTAssertTrue(usage.scoped.isEmpty)
        XCTAssertNotNil(usage.sevenDay)
    }

    /// The lock is not in `limits`; it is on the window named beside it.
    func testALockedWindowIsSpentBelowAHundred() throws {
        let locked = Data("""
        {"five_hour":{"locked_reason":"usage_limit_reached"},
         "limits":[{"kind":"session","percent":94}]}
        """.utf8)
        let usage = try XCTUnwrap(UsageAPI.usage(from: locked, now: now))
        XCTAssertTrue(usage.fiveHour?.isSpent == true)
        XCTAssertTrue(usage.isSpent)
    }

    func testAFullWindowIsSpentWithoutTheServerSayingSo() {
        XCTAssertTrue(UsageWindow(used: 1).isSpent)
        XCTAssertFalse(UsageWindow(used: 0.99).isSpent)
    }

    /// An account billed by API key has no windows, and that is not zero left.
    func testNoLimitsIsNoFigure() {
        XCTAssertNil(UsageAPI.usage(from: Data("{}".utf8), now: now))
        XCTAssertNil(UsageAPI.usage(from: Data("{\"limits\":[]}".utf8), now: now))
        XCTAssertNil(UsageAPI.usage(from: Data("not json".utf8), now: now))
    }

    func testBackingOffDoublesAndStops() {
        XCTAssertEqual(UsageAPI.delay(watched: true, failures: 0), UsageAPI.watchedInterval)
        XCTAssertEqual(UsageAPI.delay(watched: false, failures: 0), UsageAPI.restingInterval)
        XCTAssertEqual(UsageAPI.delay(watched: true, failures: 1), UsageAPI.restingInterval)
        XCTAssertEqual(UsageAPI.delay(watched: true, failures: 2), UsageAPI.restingInterval * 2)
        XCTAssertEqual(UsageAPI.delay(watched: true, failures: 40), UsageAPI.backoffCap)
    }
}

final class UsageMergeTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_700_000_000)

    private func reading(_ used: Double, source: Usage.Source, at offset: TimeInterval) -> Usage {
        Usage(fiveHour: UsageWindow(used: used), sevenDay: UsageWindow(used: used),
              source: source, reportedAt: now.addingTimeInterval(offset))
    }

    func testTheNewerReadingWins() {
        let merged = reading(0.2, source: .statusLine, at: 0)
            .merged(with: reading(0.5, source: .api, at: 60))
        XCTAssertEqual(merged.fiveHour?.used, 0.5)
        XCTAssertEqual(merged.source, .api)
        XCTAssertEqual(merged.reportedAt, now.addingTimeInterval(60))
    }

    func testAnOlderReadingCannotOverwriteANewerOne() {
        let merged = reading(0.5, source: .api, at: 60)
            .merged(with: reading(0.2, source: .statusLine, at: 0))
        XCTAssertEqual(merged.fiveHour?.used, 0.5)
        XCTAssertEqual(merged.source, .api)
    }

    /// A source that stopped carrying a window must not take it off screen.
    func testAWindowTheWinnerLacksIsBorrowed() {
        let newer = Usage(fiveHour: UsageWindow(used: 0.4), sevenDay: nil,
                          source: .api, reportedAt: now.addingTimeInterval(60))
        let older = Usage(fiveHour: nil, sevenDay: UsageWindow(used: 0.9),
                          source: .statusLine, reportedAt: now)
        let merged = newer.merged(with: older)
        XCTAssertEqual(merged.fiveHour?.used, 0.4)
        XCTAssertEqual(merged.sevenDay?.used, 0.9)
    }

    /// Only one path knows the per-model weeklies, so the other must not wipe
    /// them simply by being newer.
    func testScopedWindowsSurviveANewerStatusLine() {
        let fromApi = Usage(fiveHour: UsageWindow(used: 0.4), sevenDay: nil,
                            scoped: [ScopedWindow(label: "Fable", window: UsageWindow(used: 0.5))],
                            source: .api, reportedAt: now)
        let merged = reading(0.6, source: .statusLine, at: 60).merged(with: fromApi)
        XCTAssertEqual(merged.scoped.first?.label, "Fable")
        XCTAssertEqual(merged.fiveHour?.used, 0.6)
    }

    func testMergingWithNothingChangesNothing() {
        let only = reading(0.3, source: .api, at: 0)
        XCTAssertEqual(only.merged(with: nil), only)
    }

    func testTheBindingWindowIsTheOneNearestFull() throws {
        let usage = Usage(fiveHour: UsageWindow(used: 0.2), sevenDay: UsageWindow(used: 0.8))
        XCTAssertEqual(try XCTUnwrap(usage.binding).label, .sevenDay)
        let tight = Usage(fiveHour: UsageWindow(used: 0.9), sevenDay: UsageWindow(used: 0.8))
        XCTAssertEqual(try XCTUnwrap(tight.binding).label, .fiveHour)
        XCTAssertNil(Usage(fiveHour: nil, sevenDay: nil).binding)
    }

    /// What has been spent since a window turned over is unknown, so a stale
    /// reading has to be dropped rather than shown as an empty window.
    func testAWindowKnownToHaveTurnedOverIsSaidSo() {
        let usage = Usage(fiveHour: UsageWindow(used: 0.95,
                                                resetsAt: now.addingTimeInterval(600)),
                          sevenDay: nil, reportedAt: now)
        XCTAssertFalse(usage.hasReset(usage.fiveHour, now: now))
        XCTAssertTrue(usage.hasReset(usage.fiveHour, now: now.addingTimeInterval(601)))
        XCTAssertFalse(usage.hasReset(usage.sevenDay, now: now))
    }
}

final class CredentialsTests: XCTestCase {
    func testTheTokenAndItsExpiryAreRead() throws {
        let blob = Data("""
        {"claudeAiOauth":{"accessToken":"sk-test","refreshToken":"sk-refresh",
         "expiresAt":1788882810992,"subscriptionType":"pro",
         "scopes":["user:inference"]},"mcpOAuth":{}}
        """.utf8)
        let credential = try XCTUnwrap(Credentials.oauth(from: blob))
        XCTAssertEqual(credential.accessToken, "sk-test")
        XCTAssertEqual(credential.subscriptionType, "pro")
        XCTAssertEqual(credential.expiresAt.timeIntervalSince1970, 1_788_882_810.992, accuracy: 0.01)
    }

    /// Milliseconds today, but reading seconds as milliseconds expires a live
    /// credential in 1970 and the other way round holds a dead one for ever.
    func testAnExpiryIsReadInEitherUnit() {
        XCTAssertEqual(Credentials.expiry(1_788_882_810_992 as Double),
                       Date(timeIntervalSince1970: 1_788_882_810.992))
        XCTAssertEqual(Credentials.expiry(1_788_882_810 as Double),
                       Date(timeIntervalSince1970: 1_788_882_810))
        XCTAssertNil(Credentials.expiry(nil))
        XCTAssertNil(Credentials.expiry(0 as Double))
    }

    func testAnExpiredCredentialIsNotValid() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let credential = OAuthCredential(accessToken: "sk", expiresAt: now.addingTimeInterval(60))
        XCTAssertTrue(credential.isValid(now: now))
        XCTAssertFalse(credential.isValid(now: now.addingTimeInterval(61)))
    }

    func testNonsenseIsNoCredential() {
        XCTAssertNil(Credentials.oauth(from: Data("{}".utf8)))
        XCTAssertNil(Credentials.oauth(from: Data("{\"claudeAiOauth\":{}}".utf8)))
        XCTAssertNil(Credentials.oauth(from: Data("""
        {"claudeAiOauth":{"accessToken":"","expiresAt":1788882810992}}
        """.utf8)))
    }
}

final class UsageStoreTests: XCTestCase {
    private var url: URL { URL.temporaryDirectory.appending(path: "roost-usage-test/usage.json") }

    override func tearDown() {
        UsageStore.clear(at: url)
        super.tearDown()
    }

    func testAReadingSurvivesTheRoundTrip() throws {
        let usage = Usage(fiveHour: UsageWindow(used: 0.42, resetsAt: Date(timeIntervalSince1970: 1)),
                          sevenDay: nil,
                          scoped: [ScopedWindow(label: "Fable", window: UsageWindow(used: 0.5))],
                          source: .api,
                          reportedAt: Date(timeIntervalSince1970: 1_700_000_000))
        UsageStore.save(usage, to: url)
        XCTAssertEqual(UsageStore.load(from: url), usage)
    }

    func testNothingOnDiskIsNoReading() {
        UsageStore.clear(at: url)
        XCTAssertNil(UsageStore.load(from: url))
    }

    /// A helper from an older bundle sends the fields it knew about.
    func testAReadingWithoutTheNewerFieldsStillDecodes() throws {
        let old = Data("""
        {"fiveHour":{"used":0.25},"reportedAt":"2023-11-14T22:13:20Z"}
        """.utf8)
        let usage = try XCTUnwrap(try? JSONDecoder.wire.decode(Usage.self, from: old))
        XCTAssertEqual(usage.fiveHour?.used, 0.25)
        XCTAssertTrue(usage.scoped.isEmpty)
        XCTAssertEqual(usage.source, .statusLine)
    }
}

final class UsageFooterTests: XCTestCase {
    private let notch = CGSize(width: 200, height: 32)
    private let width: CGFloat = 470

    private func hit(y: CGFloat, x: CGFloat, rows: Int = 2) -> Bool {
        IslandGeometry.usageHit(offsetFromTop: y, offsetFromLeft: x, notch: notch,
                                islandWidth: width, rowCount: rows)
    }

    /// The band the hit test uses has to be the room the layout was given, or
    /// the meters are hovered from somewhere they are not drawn.
    func testTheFooterBandIsWhatTheLayoutReservesForIt() {
        let withFooter = IslandGeometry.expandedSize(notch: notch, sessionCount: 2, hasFooter: true)
        let without = IslandGeometry.expandedSize(notch: notch, sessionCount: 2, hasFooter: false)
        XCTAssertEqual(withFooter.height - without.height, IslandGeometry.Footer.height)
        XCTAssertEqual(IslandGeometry.footerTop(notch: notch, rowCount: 2),
                       without.height - 10)
    }

    func testTheMetersAreHoveredWhereTheyAreDrawn() {
        let top = IslandGeometry.footerTop(notch: notch, rowCount: 2)
        XCTAssertTrue(hit(y: top + 12, x: width - IslandGeometry.Footer.inset - 20))
        XCTAssertTrue(hit(y: top + 12,
                          x: width - IslandGeometry.Footer.inset
                              - IslandGeometry.Footer.metersWidth + 1))
    }

    func testNothingOutsideTheStripCounts() {
        let top = IslandGeometry.footerTop(notch: notch, rowCount: 2)
        XCTAssertFalse(hit(y: top - 1, x: width - 20))
        XCTAssertFalse(hit(y: top + IslandGeometry.Footer.height + 1, x: width - 20))
        // Left of the meters is the idle count, which is not a hover target.
        XCTAssertFalse(hit(y: top + 12, x: 40))
        // Past the inset is the island's edge.
        XCTAssertFalse(hit(y: top + 12, x: width - 4))
    }

    /// An empty list still leaves one row's worth of height, so the strip does
    /// not climb into the placeholder.
    func testAnEmptyListStillPutsTheStripBelowARow() {
        XCTAssertEqual(IslandGeometry.footerTop(notch: notch, rowCount: 0),
                       IslandGeometry.footerTop(notch: notch, rowCount: 1))
    }
}

final class UsageWordingTests: XCTestCase {
    private var utc: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }

    /// 2026-09-10T14:59:59Z
    private let reset = Date(timeIntervalSince1970: 1_789_052_399)

    func testAClockReadsTheSameInBothLanguages() {
        for language in [Language.english, .chinese] {
            XCTAssertEqual(Strings(language).clock(reset, calendar: utc), "14:59")
        }
    }

    func testADayIsNamedTheWayEachLanguageNamesIt() {
        XCTAssertEqual(Strings(.english).day(reset, calendar: utc), "Sep 10")
        XCTAssertEqual(Strings(.chinese).day(reset, calendar: utc), "9月10日")
    }

    /// The label said "what is left" while the figure was what had been spent.
    /// Neither says "left" now, because the bar fills as the window empties.
    func testTheFigureIsWhatHasBeenSpent() {
        XCTAssertEqual(Strings(.english).percent(0.76), "76%")
        XCTAssertEqual(Strings(.chinese).percent(0.115), "12%")
    }
}
