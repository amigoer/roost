import XCTest
@testable import RoostCore

final class ProcessTreeTests: XCTestCase {
    func testTheKernelAgreesWithGetppid() {
        XCTAssertEqual(ProcessTree.parent(of: getpid()), getppid())
    }

    func testTheChainStartsAtTheParentAndClimbs() {
        let chain = ProcessTree.ancestors(of: getpid())
        XCTAssertEqual(chain.first, getppid())
        XCTAssertFalse(chain.contains(getpid()))
        // launchd is where every chain ends, and it is nobody's window.
        XCTAssertFalse(chain.contains(1))
    }

    func testAProcessThatIsNotThereHasNoAncestors() {
        XCTAssertTrue(ProcessTree.ancestors(of: 999_999).isEmpty)
        XCTAssertNil(ProcessTree.parent(of: 999_999))
    }

    /// A corrupt read taken as a parent pointer is how this becomes an
    /// infinite loop, so the walk is bounded whatever the kernel says.
    func testTheWalkIsBounded() {
        XCTAssertLessThanOrEqual(ProcessTree.ancestors(of: getpid(), limit: 2).count, 2)
    }
}
