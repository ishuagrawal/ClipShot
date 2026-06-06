import XCTest
@testable import ClipShot

final class CoordinateConversionTests: XCTestCase {
    private let selection = CGRect(x: 40, y: 70, width: 100, height: 80)

    func test_annotationPointSubtractsSelectionOrigin() {
        XCTAssertEqual(
            CanvasGeometry.annotationPoint(
                fromImagePixel: CGPoint(x: 45, y: 90),
                baseSelection: selection
            ),
            CGPoint(x: 5, y: 20)
        )
    }

    func test_imagePixelAddsSelectionOrigin() {
        XCTAssertEqual(
            CanvasGeometry.imagePixel(
                fromAnnotationPoint: CGPoint(x: 5, y: 20),
                baseSelection: selection
            ),
            CGPoint(x: 45, y: 90)
        )
    }

    func test_roundTripPreservesSelectionRelativePoint() {
        let point = CGPoint(x: -12, y: 95)
        let imagePoint = CanvasGeometry.imagePixel(
            fromAnnotationPoint: point,
            baseSelection: selection
        )
        XCTAssertEqual(
            CanvasGeometry.annotationPoint(fromImagePixel: imagePoint, baseSelection: selection),
            point
        )
    }
}
