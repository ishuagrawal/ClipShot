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

    private func channels(_ color: CGColor) -> [CGFloat] {
        (color.components ?? []).prefix(3).map { $0 }
    }

    func test_offCenterContent_returnsTightBox() {
        let rect = CGRect(x: 60, y: 40, width: 120, height: 90)
        let img = image(size: CGSize(width: 300, height: 300),
                        background: .white, content: .black, contentRect: rect)

        let result = detector.detect(in: img, region: fullRegion(img))
        XCTAssertEqual(result?.box, rect)
    }

    func test_detectsBackgroundFillColor() {
        let rect = CGRect(x: 60, y: 40, width: 120, height: 90)
        let img = image(size: CGSize(width: 300, height: 300),
                        background: .white, content: .black, contentRect: rect)

        let result = detector.detect(in: img, region: fullRegion(img))
        // White background reported as the inset fill color.
        XCTAssertEqual(channels(result!.fillColor), [1, 1, 1])
    }

    func test_asymmetricMargins_detectsTopLeftContent() {
        let rect = CGRect(x: 8, y: 12, width: 40, height: 30)
        let img = image(size: CGSize(width: 200, height: 200),
                        background: .white, content: .blue, contentRect: rect)

        let result = detector.detect(in: img, region: fullRegion(img))
        XCTAssertEqual(result?.box, rect)
    }

    func test_detectsWithinSubRegion_offsetsBackToImagePx() {
        // Content drawn at top-left coords; analyze only the lower-right region.
        let rect = CGRect(x: 130, y: 130, width: 40, height: 40)
        let img = image(size: CGSize(width: 300, height: 300),
                        background: .white, content: .black, contentRect: rect)
        let region = CGRect(x: 100, y: 100, width: 200, height: 200)

        let result = detector.detect(in: img, region: region)
        XCTAssertEqual(result?.box, rect)
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

    private func pixel(_ buffer: PixelBuffer.Buffer, _ x: Int, _ y: Int) -> [Int] {
        let offset = y * buffer.bytesPerRow + x * 4
        return [Int(buffer.pixels[offset]), Int(buffer.pixels[offset + 1]), Int(buffer.pixels[offset + 2])]
    }

    func test_composer_wrapsContentInEqualFillBand() {
        let content = CGRect(x: 60, y: 40, width: 120, height: 90)
        let img = image(size: CGSize(width: 300, height: 300),
                        background: .white, content: .black, contentRect: content)
        let fill = CGColor(srgbRed: 1, green: 0, blue: 0, alpha: 1)

        let card = ContentInsetComposer.compose(screenshot: img, content: content, inset: 20, fill: fill)!
        XCTAssertEqual(card.width, 160)   // 120 + 2*20
        XCTAssertEqual(card.height, 130)  // 90 + 2*20

        let buffer = PixelBuffer.decode(card)!
        XCTAssertEqual(pixel(buffer, 2, 2), [255, 0, 0])     // inset band = fill
        XCTAssertEqual(pixel(buffer, 80, 65), [0, 0, 0])     // centered content = black
    }
}
