import XCTest
@testable import ClipShot

final class CoordinateConversionTests: XCTestCase {

    func test_documentPointSubtractsEffectiveCropOrigin() {
        let crop = CGRect(x: 40, y: 70, width: 100, height: 80)

        XCTAssertEqual(
            CanvasGeometry.documentPoint(fromImagePixel: CGPoint(x: 45, y: 90), effectiveCrop: crop),
            CGPoint(x: 5, y: 20)
        )
    }

    func test_imagePixelAddsEffectiveCropOrigin() {
        let crop = CGRect(x: 40, y: 70, width: 100, height: 80)

        XCTAssertEqual(
            CanvasGeometry.imagePixel(fromDocumentPoint: CGPoint(x: 5, y: 20), effectiveCrop: crop),
            CGPoint(x: 45, y: 90)
        )
    }

    func test_roundTripPreservesPoint() {
        let crop = CGRect(x: 13.5, y: 22.25, width: 100, height: 80)
        let point = CGPoint(x: 17.75, y: 28.5)
        let imagePoint = CanvasGeometry.imagePixel(fromDocumentPoint: point, effectiveCrop: crop)

        XCTAssertEqual(
            CanvasGeometry.documentPoint(fromImagePixel: imagePoint, effectiveCrop: crop),
            point
        )
    }
}
