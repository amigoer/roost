import XCTest
@testable import RoostCore

final class TranscriptDetailTests: XCTestCase {
    func testBashShowsTheCommand() {
        XCTAssertEqual(TranscriptReader.detail(from: ["command": "swift build"]), "swift build")
    }

    func testOnlyTheFirstLineSurvives() {
        XCTAssertEqual(TranscriptReader.detail(from: ["command": "python3 - <<'PY'\nimport os\nPY"]),
                       "python3 - <<'PY'")
    }

    func testLongValuesAreCut() {
        let detail = TranscriptReader.detail(from: ["command": String(repeating: "x", count: 200)])
        XCTAssertEqual(detail?.count, 44)
        XCTAssertTrue(detail?.hasSuffix("…") == true)
    }

    func testPathsShowTheFileNotTheTree() {
        XCTAssertEqual(TranscriptReader.detail(from: ["file_path": "/a/b/IslandView.swift"]),
                       "IslandView.swift")
    }

    /// Keyed by argument, so a tool nobody has heard of still says something.
    func testUnknownToolFallsBackToItsDescription() {
        XCTAssertEqual(TranscriptReader.detail(from: ["description": "count the rows"]),
                       "count the rows")
    }

    func testCommandWinsOverWeakerKeys() {
        XCTAssertEqual(TranscriptReader.detail(from: ["description": "run it", "command": "ls"]), "ls")
    }

    func testNothingUsableIsNil() {
        XCTAssertNil(TranscriptReader.detail(from: ["timeout": 30]))
        XCTAssertNil(TranscriptReader.detail(from: ["command": "   "]))
        XCTAssertNil(TranscriptReader.detail(from: nil))
    }
}

/// The session's mode decides whether a tool call is worth holding at all, and
/// the transcript is the only place a session started in a terminal records it.
final class TranscriptModeTests: XCTestCase {
    private func facts(_ lines: [String]) throws -> TranscriptReader.Facts {
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appending(path: "roost-mode-\(UUID().uuidString).jsonl")
        try lines.joined(separator: "\n").write(to: url, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: url) }
        return try XCTUnwrap(TranscriptReader.facts(url: url))
    }

    func testTheModeComesOffTheLatestTurn() throws {
        let read = try facts([
            #"{"type":"user","permissionMode":"default","message":{"role":"user","content":[]}}"#,
            #"{"type":"user","permissionMode":"auto","message":{"role":"user","content":[]}}"#,
        ])
        XCTAssertEqual(read.permissionMode, "auto")
    }

    /// Changing mode mid-turn writes a line of its own, and that is the one in
    /// force for the tool calls after it.
    func testASwitchMidTurnIsTheCurrentMode() throws {
        let read = try facts([
            #"{"type":"user","permissionMode":"auto","message":{"role":"user","content":[]}}"#,
            #"{"type":"permission-mode","permissionMode":"default","sessionId":"s"}"#,
        ])
        XCTAssertEqual(read.permissionMode, "default")
    }

    func testATranscriptThatNeverSaysIsNoAnswer() throws {
        let read = try facts([#"{"type":"user","message":{"role":"user","content":[]}}"#])
        XCTAssertNil(read.permissionMode)
    }
}
