import CoreGraphics
import XCTest
@testable import ClipShot

final class NativeWindowMatcherTests: XCTestCase {

    func testScreencaptureRectArgumentRoundsOutwardToContainSelection() {
        let arg = NativeScreencaptureCLI.rectArgument(
            for: CGRect(x: 12.4, y: 80.6, width: 200.4, height: 100.2)
        )

        XCTAssertEqual(arg, "12,80,201,101")
    }

    func testWindowCornerRadiusRescalesIntoColorGrid() {
        let radius = NativeWindowShaping.cornerRadius(
            shapeRadius: 12,
            shapeSize: CGSize(width: 800, height: 500),
            colorSize: CGSize(width: 1600, height: 1000)
        )

        XCTAssertEqual(radius, 24)
    }

    func testWindowCornerRadiusUnchangedForEqualGrids() {
        let radius = NativeWindowShaping.cornerRadius(
            shapeRadius: 18,
            shapeSize: CGSize(width: 800, height: 500),
            colorSize: CGSize(width: 800, height: 500)
        )

        XCTAssertEqual(radius, 18)
    }

}
