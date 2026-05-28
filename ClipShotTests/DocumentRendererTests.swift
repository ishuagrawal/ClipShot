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
}
