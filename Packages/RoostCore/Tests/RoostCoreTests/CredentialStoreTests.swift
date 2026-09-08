import XCTest
@testable import RoostCore

/// How often the keychain is actually touched.
///
/// Every touch of Claude Code's item is a dialog for any build that is not on
/// its access list, and ad-hoc signing means that is every build after an
/// update. The figure in the footer is worth one read; it is not worth one a
/// minute.
final class CredentialStoreTests: XCTestCase {
    private let start = Date(timeIntervalSince1970: 1_000_000)

    /// Counts reads, so the test is about the keychain traffic rather than the
    /// value that comes back.
    private final class Counter: @unchecked Sendable {
        private(set) var reads = 0
        var answer: OAuthCredential?
        init(_ answer: OAuthCredential?) { self.answer = answer }
        func read() -> OAuthCredential? {
            reads += 1
            return answer
        }
    }

    private func good(_ expiresIn: TimeInterval) -> OAuthCredential {
        OAuthCredential(accessToken: "t", expiresAt: start.addingTimeInterval(expiresIn))
    }

    func testAGoodCredentialIsReadOnceHoweverOftenItIsAskedFor() async {
        let counter = Counter(good(3600))
        let store = CredentialStore { counter.read() }
        // An hour of polling at the watched interval.
        for minute in 0..<60 {
            _ = await store.current(now: start.addingTimeInterval(Double(minute) * 60))
        }
        XCTAssertEqual(counter.reads, 1)
    }

    func testItLooksAgainOnceWhatItHoldsHasRunOut() async {
        let counter = Counter(good(600))
        let store = CredentialStore { counter.read() }
        let first = await store.current(now: start)
        XCTAssertNotNil(first)
        XCTAssertEqual(counter.reads, 1)
        // Past the token's own expiry, and past the wait.
        counter.answer = good(4 * 3600)
        let second = await store.current(now: start.addingTimeInterval(1800))
        XCTAssertNotNil(second)
        XCTAssertEqual(counter.reads, 2)
    }

    /// The case that made this necessary: nothing to find, and a poll every
    /// minute. Without a wait that is a dialog every minute.
    func testNothingToFindIsNotAskedForEveryTick() async {
        let counter = Counter(nil)
        let store = CredentialStore { counter.read() }
        for minute in 0..<60 {
            _ = await store.current(now: start.addingTimeInterval(Double(minute) * 60))
        }
        // Sixty asks across fifty-nine minutes: one at the start and one every
        // fifteen after it. Without the wait it would be sixty dialogs.
        XCTAssertEqual(counter.reads, 4)
    }

    func testAnExpiredCredentialIsNoCredential() async {
        let expired = good(-1)
        let store = CredentialStore { expired }
        let found = await store.current(now: start)
        XCTAssertNil(found)
    }

    /// Turning the switch on is somebody asking for the figure now.
    func testAskingDirectlyDoesNotWaitOutTheInterval() async {
        let counter = Counter(nil)
        let store = CredentialStore { counter.read() }
        _ = await store.current(now: start)
        XCTAssertEqual(counter.reads, 1)
        counter.answer = good(3600)
        let asked = await store.refresh(now: start.addingTimeInterval(5))
        XCTAssertNotNil(asked)
        XCTAssertEqual(counter.reads, 2)
    }
}
