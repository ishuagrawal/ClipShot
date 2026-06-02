import CoreGraphics
import XCTest
@testable import ClipShot

final class ZoomMathTests: XCTestCase {

    func testClampBoundsToMinAndMax() {
        XCTAssertEqual(ZoomMath.clamp(0.001), ZoomMath.minMagnification)
        XCTAssertEqual(ZoomMath.clamp(999), ZoomMath.maxMagnification)
        XCTAssertEqual(ZoomMath.clamp(1), 1)
    }

    func testSteppedFromStopMovesToNextStop() {
        XCTAssertEqual(ZoomMath.stepped(1, direction: 1), 1.25, accuracy: 0.0001)
        XCTAssertEqual(ZoomMath.stepped(1, direction: -1), 0.75, accuracy: 0.0001)
    }

    func testSteppedFromOffGridSnapsToNiceStop() {
        // 42% zoom-in -> 50%, zoom-out -> 33%.
        XCTAssertEqual(ZoomMath.stepped(0.42, direction: 1), 0.5, accuracy: 0.0001)
        XCTAssertEqual(ZoomMath.stepped(0.42, direction: -1), 0.33, accuracy: 0.0001)
    }

    func testSteppedZeroDirectionClampsOnly() {
        XCTAssertEqual(ZoomMath.stepped(2, direction: 0), 2)
        XCTAssertEqual(ZoomMath.stepped(999, direction: 0), ZoomMath.maxMagnification)
    }

    func testSteppedClampsAtCeiling() {
        XCTAssertEqual(ZoomMath.stepped(ZoomMath.maxMagnification, direction: 1), ZoomMath.maxMagnification)
        XCTAssertEqual(ZoomMath.stepped(999, direction: 1), ZoomMath.maxMagnification)
    }

    func testSteppedClampsAtFloor() {
        XCTAssertEqual(ZoomMath.stepped(ZoomMath.minMagnification, direction: -1), ZoomMath.minMagnification)
        XCTAssertEqual(ZoomMath.stepped(0.001, direction: -1), ZoomMath.minMagnification)
    }

    func testZoomStopsSortedAndWithinBounds() {
        XCTAssertEqual(ZoomMath.zoomStops, ZoomMath.zoomStops.sorted())
        XCTAssertEqual(ZoomMath.zoomStops.first, ZoomMath.minMagnification)
        XCTAssertEqual(ZoomMath.zoomStops.last, ZoomMath.maxMagnification)
    }

    func testPercentLabelRoundsToWholePercent() {
        XCTAssertEqual(ZoomMath.percentLabel(1), "100%")
        XCTAssertEqual(ZoomMath.percentLabel(0.25), "25%")
        XCTAssertEqual(ZoomMath.percentLabel(0.333), "33%")
        XCTAssertEqual(ZoomMath.percentLabel(4), "400%")
    }

    func testPresetsWithinBounds() {
        for preset in ZoomMath.presets {
            XCTAssertGreaterThanOrEqual(preset, ZoomMath.minMagnification)
            XCTAssertLessThanOrEqual(preset, ZoomMath.maxMagnification)
        }
    }
}
