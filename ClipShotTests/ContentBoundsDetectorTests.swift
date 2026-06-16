import XCTest
@testable import ClipShot

final class ContentBoundsDetectorTests: XCTestCase {

    private let detector = ContentBoundsDetector()

    /// Solid background with a filled content rect at a top-left position.
    private func image(size: CGSize, background: NSColor, content: NSColor, contentRect: CGRect) -> CGImage {
        let w = Int(size.width), h = Int(size.height)
        let cs = CGColorSpace(name: CGColorSpace.sRGB)!
        let ctx = CGContext(
            data: nil, width: w, height: h, bitsPerComponent: 8,
            bytesPerRow: w * 4, space: cs,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
                | CGBitmapInfo.byteOrder32Big.rawValue
        )!
        ctx.setFillColor(background.cgColor)
        ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
        // Top-left origin so contentRect reads from the top, matching the detector.
        ctx.translateBy(x: 0, y: CGFloat(h))
        ctx.scaleBy(x: 1, y: -1)
        ctx.setFillColor(content.cgColor)
        ctx.fill(contentRect)
        return ctx.makeImage()!
    }

    private func fullRegion(_ image: CGImage) -> CGRect {
        CGRect(x: 0, y: 0, width: image.width, height: image.height)
    }

    func test_offCenterContent_returnsTightBox() {
        let rect = CGRect(x: 60, y: 40, width: 120, height: 90)
        let img = image(size: CGSize(width: 300, height: 300),
                        background: .white, content: .black, contentRect: rect)

        let box = detector.detect(in: img, region: fullRegion(img))
        XCTAssertEqual(box, rect)
    }

    func test_asymmetricMargins_detectsTopLeftContent() {
        let rect = CGRect(x: 8, y: 12, width: 40, height: 30)
        let img = image(size: CGSize(width: 200, height: 200),
                        background: .white, content: .blue, contentRect: rect)

        let box = detector.detect(in: img, region: fullRegion(img))
        XCTAssertEqual(box, rect)
    }

    func test_detectsWithinSubRegion_offsetsBackToImagePx() {
        // Content drawn at top-left coords; analyze only the lower-right region.
        let rect = CGRect(x: 130, y: 130, width: 40, height: 40)
        let img = image(size: CGSize(width: 300, height: 300),
                        background: .white, content: .black, contentRect: rect)
        let region = CGRect(x: 100, y: 100, width: 200, height: 200)

        let box = detector.detect(in: img, region: region)
        XCTAssertEqual(box, rect)
    }

    func test_uniformImage_returnsNil() {
        let img = TestImage.solid(.white, size: CGSize(width: 120, height: 120))
        XCTAssertNil(detector.detect(in: img, region: fullRegion(img)))
    }

    func test_regionSmallerThanMinimum_returnsNil() {
        let img = TestImage.solid(.white, size: CGSize(width: 120, height: 120))
        let tiny = CGRect(x: 0, y: 0, width: 4, height: 4)
        XCTAssertNil(detector.detect(in: img, region: tiny))
    }

    func test_detectedContentSmallerThanMinimum_returnsNil() {
        let img = image(size: CGSize(width: 120, height: 120),
                        background: .white,
                        content: .black,
                        contentRect: CGRect(x: 40, y: 40, width: 4, height: 4))

        XCTAssertNil(detector.detect(in: img, region: fullRegion(img)))
    }
}
