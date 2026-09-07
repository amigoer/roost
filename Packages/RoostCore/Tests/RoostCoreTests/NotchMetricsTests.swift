import XCTest
import CoreGraphics
@testable import RoostCore

final class NotchMetricsTests: XCTestCase {
    // Values read off this machine: 14-inch MacBook Pro, default scaling.
    private let left = CGRect(x: 0, y: 950, width: 663.5, height: 32)
    private let right = CGRect(x: 848.5, y: 950, width: 663.5, height: 32)

    func testMatchesMeasuredHardware() {
        let notch = NotchMetrics.notchRect(auxiliaryTopLeft: left, auxiliaryTopRight: right)
        XCTAssertEqual(notch, CGRect(x: 663.5, y: 950, width: 185, height: 32))
    }

    func testNoNotchWhenAreasAreMissing() {
        XCTAssertNil(NotchMetrics.notchRect(auxiliaryTopLeft: nil, auxiliaryTopRight: right))
        XCTAssertNil(NotchMetrics.notchRect(auxiliaryTopLeft: left, auxiliaryTopRight: nil))
        XCTAssertNil(NotchMetrics.notchRect(auxiliaryTopLeft: nil, auxiliaryTopRight: nil))
    }

    func testRejectsNonPositiveGap() {
        let overlapping = CGRect(x: 100, y: 950, width: 663.5, height: 32)
        XCTAssertNil(NotchMetrics.notchRect(auxiliaryTopLeft: left, auxiliaryTopRight: overlapping))
    }

    func testHeightIsNotHardcoded() {
        // "More Space" scaling reports a 38pt notch; nothing may assume 32.
        let l = CGRect(x: 0, y: 1131, width: 790, height: 38)
        let r = CGRect(x: 1010, y: 1131, width: 790, height: 38)
        let notch = NotchMetrics.notchRect(auxiliaryTopLeft: l, auxiliaryTopRight: r)
        XCTAssertEqual(notch?.height, 38)
        XCTAssertEqual(notch?.width, 220)
    }

    func testFallbackIsCentred() {
        let screen = CGRect(x: 0, y: 0, width: 1920, height: 1080)
        let rect = NotchMetrics.fallbackRect(screenFrame: screen, menuBarHeight: 24)
        XCTAssertEqual(rect.midX, screen.midX)
        XCTAssertEqual(rect.maxY, screen.maxY)
        XCTAssertEqual(rect.height, 24)
    }
}
