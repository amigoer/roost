import XCTest
@testable import RoostCore

final class ChirpTests: XCTestCase {
    func testTheWavIsAWavMacosWillPlay() throws {
        let data = Chirp.waiting.wav()
        XCTAssertEqual(String(decoding: data[0..<4], as: UTF8.self), "RIFF")
        XCTAssertEqual(String(decoding: data[8..<12], as: UTF8.self), "WAVE")
        // The size field counts everything after it, which is how a player
        // knows where the samples stop.
        let declared = data[4..<8].withUnsafeBytes { $0.loadUnaligned(as: UInt32.self) }
        XCTAssertEqual(Int(UInt32(littleEndian: declared)), data.count - 8)
    }

    func testEveryNoteIsRendered() {
        let samples = Chirp.waiting.render(sampleRate: Chirp.sampleRate)
        let expected = Chirp.waiting.notes.reduce(0) { $0 + Int($1.seconds * Chirp.sampleRate) }
        XCTAssertEqual(samples.count, expected)
    }

    /// A square wave cut off mid-cycle is a click, so every note has to end
    /// near silence.
    func testANoteFadesOutRatherThanStopping() throws {
        let samples = Chirp.done.render(sampleRate: Chirp.sampleRate)
        let last = try XCTUnwrap(samples.last)
        XCTAssertLessThan(abs(Int(last)), 400)
    }

    /// Rising is something that needs you, falling is something that is done,
    /// and that is the whole of what these have to say.
    func testPitchCarriesTheMeaning() {
        let needsYou = Chirp.waiting.notes.map(\.hertz)
        XCTAssertEqual(needsYou, needsYou.sorted())
        let finished = Chirp.done.notes.map(\.hertz)
        XCTAssertEqual(finished, finished.sorted(by: >))
    }

    func testNothingIsLoudEnoughToStartle() {
        for chirp in [Chirp.waiting, Chirp.done] {
            let peak = chirp.render(sampleRate: Chirp.sampleRate).map { abs(Int($0)) }.max() ?? 0
            XCTAssertLessThan(peak, Int(0.25 * 32_767))
            XCTAssertLessThan(chirp.duration, 0.4)
        }
    }
}

final class AnnouncerTests: XCTestCase {
    private func session(_ id: String, _ state: SessionState) -> Session {
        Session(id: id, pid: 1, name: id, cwd: "/tmp/perch", entrypoint: "cli",
                startedAt: .distantPast, state: state, stateSince: .distantPast,
                activity: nil, lastActivityAt: .distantPast)
    }

    /// Everything in the first snapshot was already true before the app
    /// opened, and announcing a whole fleet at launch is how a sound becomes
    /// one nobody keeps on.
    func testTheFirstSnapshotIsSilent() {
        var announcer = Announcer()
        XCTAssertNil(announcer.cue(for: [session("a", .blocked(.question)),
                                         session("b", .done)]))
    }

    func testStoppingOnSomethingOnlyYouCanAnswerIsSaidOutLoud() {
        var announcer = Announcer()
        _ = announcer.cue(for: [session("a", .running)])
        XCTAssertEqual(announcer.cue(for: [session("a", .blocked(.question))]), .waiting)
    }

    func testATurnEndingIsSaidMoreQuietly() {
        var announcer = Announcer()
        _ = announcer.cue(for: [session("a", .running)])
        XCTAssertEqual(announcer.cue(for: [session("a", .done)]), .done)
    }

    /// A session can move between two kinds of blocked while it waits, and
    /// none of that is worth a second noise.
    func testStayingBlockedSaysNothingFurther() {
        var announcer = Announcer()
        _ = announcer.cue(for: [session("a", .running)])
        XCTAssertEqual(announcer.cue(for: [session("a", .blocked(.question))]), .waiting)
        XCTAssertNil(announcer.cue(for: [session("a", .blocked(.stalledTool(name: "Bash")))]))
        XCTAssertNil(announcer.cue(for: [session("a", .blocked(.permissionPrompt(tool: "Bash")))]))
    }

    /// Two chirps on top of each other say less than either alone.
    func testTheOneThatNeedsAPersonWins() {
        var announcer = Announcer()
        _ = announcer.cue(for: [session("a", .running), session("b", .running)])
        XCTAssertEqual(announcer.cue(for: [session("a", .blocked(.question)),
                                           session("b", .done)]), .waiting)
    }

    /// A session that appears already blocked is new information, unlike one
    /// that was blocked before the app was watching.
    func testASessionThatArrivesBlockedIsAnnounced() {
        var announcer = Announcer()
        _ = announcer.cue(for: [session("a", .running)])
        XCTAssertEqual(announcer.cue(for: [session("a", .running),
                                           session("b", .blocked(.question))]), .waiting)
    }

    func testNothingChangingSaysNothing() {
        var announcer = Announcer()
        _ = announcer.cue(for: [session("a", .running)])
        XCTAssertNil(announcer.cue(for: [session("a", .running)]))
    }

    /// A window running out is a session stopping, from the other end.
    func testAWindowRunningOutIsAnnouncedOnce() {
        var announcer = Announcer()
        XCTAssertNil(announcer.cue(forSpentWindow: false))
        XCTAssertEqual(announcer.cue(forSpentWindow: true), .waiting)
        XCTAssertNil(announcer.cue(forSpentWindow: true))
    }

    /// A window already spent when the app opened is not news.
    func testAWindowFoundSpentAtLaunchSaysNothing() {
        var announcer = Announcer()
        XCTAssertNil(announcer.cue(forSpentWindow: true))
        XCTAssertNil(announcer.cue(forSpentWindow: true))
    }

    /// It comes back, and then it goes again.
    func testTheSecondCrossingIsAnnouncedToo() {
        var announcer = Announcer()
        _ = announcer.cue(forSpentWindow: false)
        XCTAssertEqual(announcer.cue(forSpentWindow: true), .waiting)
        XCTAssertNil(announcer.cue(forSpentWindow: false))
        XCTAssertEqual(announcer.cue(forSpentWindow: true), .waiting)
    }

    /// The two baselines are separate: a fleet already running must not eat the
    /// window's first look, nor the other way round.
    func testTheWindowKeepsItsOwnBaseline() {
        var announcer = Announcer()
        _ = announcer.cue(for: [session("a", .running)])
        XCTAssertNil(announcer.cue(forSpentWindow: false))
        XCTAssertEqual(announcer.cue(forSpentWindow: true), .waiting)
    }
}
