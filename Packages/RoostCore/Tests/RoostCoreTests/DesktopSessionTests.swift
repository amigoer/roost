import XCTest
@testable import RoostCore

final class DesktopSessionTests: XCTestCase {
    private func session(model: String?) -> DesktopSession {
        DesktopSession(title: nil, model: model, permissionMode: nil)
    }

    func testModelLabelDropsThePrefix() {
        XCTAssertEqual(session(model: "claude-opus-4-6").modelLabel, "Opus 4.6")
    }

    func testModelLabelDropsTheTrainingDate() {
        XCTAssertEqual(session(model: "claude-sonnet-4-5-20250929").modelLabel, "Sonnet 4.5")
    }

    /// Older ids put the version in front of the family name.
    func testModelLabelHandlesTheOldOrder() {
        XCTAssertEqual(session(model: "claude-3-5-sonnet-20241022").modelLabel, "Sonnet 3.5")
    }

    func testModelLabelSurvivesAVersionlessName() {
        XCTAssertEqual(session(model: "claude-haiku").modelLabel, "Haiku")
    }

    func testNoModelIsNoLabel() {
        XCTAssertNil(session(model: nil).modelLabel)
    }
}
