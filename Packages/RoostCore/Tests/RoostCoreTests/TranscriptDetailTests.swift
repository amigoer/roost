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
