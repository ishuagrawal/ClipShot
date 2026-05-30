import XCTest
@testable import ClipShot

final class DocumentRendererTests: XCTestCase {

    func test_render_v0_outputSize_matchesEffectiveCropInPixels() throws {
        let (_, doc) = FixtureDocument.basicPair()
        let rendered = try XCTUnwrap(DocumentRenderer.render(doc))
        let crop = doc.effectiveCrop.integral
        XCTAssertEqual(rendered.width, Int(crop.width), "output width must equal effectiveCrop")
        XCTAssertEqual(rendered.height, Int(crop.height), "output height must equal effectiveCrop")
    }

    func test_render_v0_pixelEqualToLegacyDOMCaptureCrop() throws {
        let (session, doc) = FixtureDocument.basicPair()

        let legacyPNG = try XCTUnwrap(session.selectedCropPNGData())
        let newCGImage = try XCTUnwrap(DocumentRenderer.render(doc))
        let newPNG = try XCTUnwrap(
            NSBitmapImageRep(cgImage: newCGImage).representation(using: .png, properties: [:])
        )

        let legacy = try XCTUnwrap(PixelBuffer.decode(legacyPNG))
        let new = try XCTUnwrap(PixelBuffer.decode(newPNG))

        XCTAssertEqual(legacy.width, new.width, "width must match legacy crop")
        XCTAssertEqual(legacy.height, new.height, "height must match legacy crop")
        XCTAssertEqual(legacy.pixels, new.pixels, "decoded RGBA must be identical")
    }

    func test_render_v0_topLeftPixel_isFromSelectionOrigin() throws {
        let (_, doc) = FixtureDocument.basicPair()
        let rendered = try XCTUnwrap(DocumentRenderer.render(doc))
        let renderedBuf = try XCTUnwrap(PixelBuffer.decode(rendered))
        let screenshotBuf = try XCTUnwrap(PixelBuffer.decode(doc.screenshot))

        let originX = Int(doc.baseSelection.minX)
        let originY = Int(doc.baseSelection.minY)
        let screenshotIndex = originY * screenshotBuf.bytesPerRow + originX * 4
        let renderedIndex = 0
        for byte in 0..<4 {
            XCTAssertEqual(
                renderedBuf.pixels[renderedIndex + byte],
                screenshotBuf.pixels[screenshotIndex + byte],
                "top-left pixel byte \(byte) must match screenshot at selection origin"
            )
        }
    }

    func test_render_v0_fractionalSelection_matchesIntegralCropWithoutResampling() throws {
        let screenshot = FixtureDocument.makeStripedImage(size: CGSize(width: 40, height: 30))
        let selection = CGRect(x: 5.25, y: 6.5, width: 12.2, height: 9.1)
        let doc = EditorDocument(
            screenshot: screenshot,
            viewport: CGSize(width: 40, height: 30),
            pageTitle: "Fractional",
            pageURL: "https://example.com",
            baseSelection: selection
        )

        let rendered = try XCTUnwrap(DocumentRenderer.render(doc))
        let expectedCrop = try XCTUnwrap(screenshot.cropping(to: selection.integral))
        let renderedBuf = try XCTUnwrap(PixelBuffer.decode(rendered))
        let expectedBuf = try XCTUnwrap(PixelBuffer.decode(expectedCrop))

        XCTAssertEqual(renderedBuf.width, expectedBuf.width)
        XCTAssertEqual(renderedBuf.height, expectedBuf.height)
        XCTAssertEqual(renderedBuf.pixels, expectedBuf.pixels)
    }

    func test_render_outputSize_includesPadding() throws {
        let image = try XCTUnwrap(DocumentRenderer.render(paddedDoc(padding: 10, background: .none)))
        XCTAssertEqual(image.width, 100)
        XCTAssertEqual(image.height, 80)
    }

    func test_render_noneBackground_marginIsTransparent() throws {
        let image = try XCTUnwrap(DocumentRenderer.render(paddedDoc(padding: 10, background: .none)))
        let buffer = try XCTUnwrap(PixelBuffer.decode(image))
        XCTAssertEqual(buffer.pixels[3], 0, "top-left margin alpha must be 0 for .none")
    }

    func test_render_solidBackground_fillsMarginAndKeepsScreenshot() throws {
        let blue = CGColor(red: 0, green: 0, blue: 1, alpha: 1)
        let image = try XCTUnwrap(DocumentRenderer.render(paddedDoc(padding: 10, background: .solidColor(blue))))
        let buffer = try XCTUnwrap(PixelBuffer.decode(image))

        XCTAssertEqual(Int(buffer.pixels[2]), 255, accuracy: 2)
        XCTAssertEqual(Int(buffer.pixels[3]), 255)

        let padding = 10
        let inside = padding * buffer.bytesPerRow + padding * 4
        XCTAssertEqual(Int(buffer.pixels[inside]), 255, accuracy: 2)
        XCTAssertEqual(Int(buffer.pixels[inside + 2]), 0, accuracy: 2)
    }

    func test_render_gradientBackground_marginIsOpaque() throws {
        let start = CGColor(red: 0, green: 0, blue: 0, alpha: 1)
        let end = CGColor(red: 1, green: 1, blue: 1, alpha: 1)
        let image = try XCTUnwrap(
            DocumentRenderer.render(
                paddedDoc(
                    padding: 20,
                    background: .gradient(start: start, end: end, angleDegrees: 90)
                )
            )
        )
        let buffer = try XCTUnwrap(PixelBuffer.decode(image))
        XCTAssertEqual(buffer.pixels[3], 255, "gradient margin must be opaque")
    }

    func test_render_blurExtendBackground_marginIsOpaque() throws {
        let image = try XCTUnwrap(DocumentRenderer.render(paddedDoc(padding: 20, background: .blurExtend(radius: 12))))
        let buffer = try XCTUnwrap(PixelBuffer.decode(image))
        XCTAssertEqual(buffer.pixels[3], 255, "blur-extend margin must be opaque")
    }

    private func paddedDoc(padding: CGFloat, background: BackgroundStyle) -> EditorDocument {
        EditorDocument(
            screenshot: TestImage.solid(.red, size: CGSize(width: 200, height: 200)),
            viewport: CGSize(width: 200, height: 200),
            pageTitle: "t",
            pageURL: "u",
            baseSelection: CGRect(x: 50, y: 50, width: 80, height: 60),
            padding: PaddingConfig(top: padding, right: padding, bottom: padding, left: padding),
            background: background
        )
    }
}
