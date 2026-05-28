import XCTest
@testable import ClipShot

final class EditorDocumentTests: XCTestCase {

    private func makeDoc(
        screenshotSize: CGSize = CGSize(width: 800, height: 600),
        selection: CGRect = CGRect(x: 100, y: 100, width: 200, height: 150),
        padding: PaddingConfig = .zero
    ) -> EditorDocument {
        let cgImage = TestImage.solid(.red, size: screenshotSize)
        return EditorDocument(
            screenshot: cgImage,
            viewport: screenshotSize,
            pageTitle: "Test",
            pageURL: "https://example.com",
            baseSelection: selection,
            padding: padding,
            background: .none,
            annotations: []
        )
    }

    func test_effectiveCrop_withZeroPadding_equalsBaseSelection() {
        let doc = makeDoc()
        XCTAssertEqual(doc.effectiveCrop, CGRect(x: 100, y: 100, width: 200, height: 150))
    }

    func test_effectiveCrop_expandsByPaddingPerSide() {
        let doc = makeDoc(padding: PaddingConfig(top: 10, right: 20, bottom: 30, left: 40))
        XCTAssertEqual(doc.effectiveCrop, CGRect(x: 60, y: 90, width: 260, height: 190))
    }

    func test_effectiveCrop_mayExceedScreenshotBounds() {
        let doc = makeDoc(
            screenshotSize: CGSize(width: 200, height: 200),
            selection: CGRect(x: 10, y: 10, width: 50, height: 50),
            padding: PaddingConfig(top: 100, right: 200, bottom: 100, left: 100)
        )
        XCTAssertEqual(doc.effectiveCrop, CGRect(x: -90, y: -90, width: 350, height: 250))
    }

    func test_init_clampsDegenerateSelectionToEightByEight() {
        let doc = makeDoc(selection: CGRect(x: 50, y: 50, width: 0.4, height: 0.6))
        XCTAssertEqual(doc.baseSelection.width, 8)
        XCTAssertEqual(doc.baseSelection.height, 8)
    }

    func test_version_bumpsOnMutation() {
        var doc = makeDoc()
        let v0 = doc.version
        doc.padding = PaddingConfig(top: 5, right: 5, bottom: 5, left: 5)
        XCTAssertEqual(doc.version, v0 + 1)
        doc.background = .solidColor(CGColor(red: 0, green: 0, blue: 0, alpha: 1))
        XCTAssertEqual(doc.version, v0 + 2)
        doc.annotations = []
        XCTAssertEqual(doc.version, v0 + 3)
    }

    func test_paddingConfig_uniformReturnsValueOnlyWhenAllFourEqual() {
        XCTAssertEqual(PaddingConfig(top: 5, right: 5, bottom: 5, left: 5).uniform, 5)
        XCTAssertNil(PaddingConfig(top: 5, right: 5, bottom: 5, left: 6).uniform)
        XCTAssertEqual(PaddingConfig.zero.uniform, 0)
    }
}

/// Small image helper used across tests.
enum TestImage {
    static func solid(_ color: NSColor, size: CGSize) -> CGImage {
        let w = Int(size.width)
        let h = Int(size.height)
        let cs = CGColorSpace(name: CGColorSpace.sRGB)!
        let ctx = CGContext(
            data: nil, width: w, height: h, bitsPerComponent: 8,
            bytesPerRow: w * 4, space: cs,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
                | CGBitmapInfo.byteOrder32Big.rawValue
        )!
        ctx.setFillColor(color.cgColor)
        ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
        return ctx.makeImage()!
    }
}
