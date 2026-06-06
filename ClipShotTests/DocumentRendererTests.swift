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

    func test_render_selectionCornerRadiiMasksScreenshotCorners() throws {
        let doc = EditorDocument(
            screenshot: TestImage.solid(.red, size: CGSize(width: 48, height: 48)),
            viewport: CGSize(width: 48, height: 48),
            pageTitle: "Rounded",
            pageURL: "https://example.com",
            baseSelection: CGRect(x: 4, y: 4, width: 40, height: 40),
            selectionCornerRadii: .uniform(14),
            background: .none
        )

        let image = try XCTUnwrap(DocumentRenderer.render(doc))
        let buffer = try XCTUnwrap(PixelBuffer.decode(image))

        XCTAssertEqual(buffer.pixels[3], 0, "rounded selection corner must be transparent")

        let center = 20 * buffer.bytesPerRow + 20 * 4
        XCTAssertGreaterThan(Int(buffer.pixels[center]), 235)
        XCTAssertEqual(Int(buffer.pixels[center + 3]), 255)
    }

    func test_render_zeroPaddingDoesNotDrawSelectedBackgroundBehindRoundedCorners() throws {
        let doc = EditorDocument(
            screenshot: TestImage.solid(.red, size: CGSize(width: 48, height: 48)),
            viewport: CGSize(width: 48, height: 48),
            pageTitle: "Rounded",
            pageURL: "https://example.com",
            baseSelection: CGRect(x: 4, y: 4, width: 40, height: 40),
            selectionCornerRadii: .uniform(14),
            padding: .zero,
            background: .solidColor(.init(red: 0, green: 0, blue: 1, alpha: 1))
        )

        let image = try XCTUnwrap(DocumentRenderer.render(doc))
        let buffer = try XCTUnwrap(PixelBuffer.decode(image))

        XCTAssertEqual(buffer.pixels[3], 0, "zero padding must leave rounded corners transparent")
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

    func test_render_blurExtendBackground_usesCurrentScreenshotForSameSizedCaptures() throws {
        let red = TestImage.solid(.red, size: CGSize(width: 91, height: 91))
        let blue = TestImage.solid(.blue, size: CGSize(width: 91, height: 91))
        _ = DocumentRenderer.render(
            document(
                screenshot: red,
                selection: CGRect(x: 25, y: 25, width: 41, height: 41),
                padding: 25,
                background: .blurExtend(radius: 7)
            )
        )

        let image = try XCTUnwrap(
            DocumentRenderer.render(
                document(
                    screenshot: blue,
                    selection: CGRect(x: 25, y: 25, width: 41, height: 41),
                    padding: 25,
                    background: .blurExtend(radius: 7)
                )
            )
        )
        let buffer = try XCTUnwrap(PixelBuffer.decode(image))

        XCTAssertLessThan(Int(buffer.pixels[0]), 20)
        XCTAssertLessThan(Int(buffer.pixels[1]), 20)
        XCTAssertGreaterThan(Int(buffer.pixels[2]), 235)
    }

    func test_render_blurExtendBackground_drawsUprightInPadding() throws {
        let image = try XCTUnwrap(
            DocumentRenderer.render(
                document(
                    screenshot: verticalSplitImage(size: CGSize(width: 73, height: 73)),
                    selection: CGRect(x: 20, y: 20, width: 33, height: 33),
                    padding: 20,
                    background: .blurExtend(radius: 0)
                )
            )
        )
        let buffer = try XCTUnwrap(PixelBuffer.decode(image))

        // The fixture is created in Core Graphics' y-up space, so its visual
        // top half is blue. Upright rendering must keep the output top-left blue.
        XCTAssertLessThan(Int(buffer.pixels[0]), 20)
        XCTAssertLessThan(Int(buffer.pixels[1]), 80)
        XCTAssertGreaterThan(Int(buffer.pixels[2]), 235)
    }

    func test_render_arrow_overridesScreenshotPixels() throws {
        var doc = paddedDoc(padding: 0, background: .none)
        doc.annotations = [
            Annotation(
                kind: .arrow(
                    from: CGPoint(x: 5, y: 5),
                    to: CGPoint(x: 70, y: 50),
                    color: CGColor(red: 0, green: 0, blue: 1, alpha: 1),
                    weight: 8
                )
            )
        ]

        let image = try XCTUnwrap(DocumentRenderer.render(doc))
        let buffer = try XCTUnwrap(PixelBuffer.decode(image))
        let midX = 37
        let midY = 27
        let index = midY * buffer.bytesPerRow + midX * 4

        XCTAssertEqual(Int(buffer.pixels[index + 3]), 255)
        XCTAssertLessThan(Int(buffer.pixels[index]), 80)
        XCTAssertGreaterThan(Int(buffer.pixels[index + 2]), 150)
    }

    func test_render_rect_strokeChangesEdgePixels() throws {
        var doc = paddedDoc(padding: 0, background: .none)
        doc.annotations = [
            Annotation(
                kind: .rect(
                    frame: CGRect(x: 10, y: 10, width: 50, height: 30),
                    stroke: CGColor(red: 0, green: 1, blue: 0, alpha: 1),
                    fill: nil,
                    weight: 4,
                    cornerRadius: 0
                )
            )
        ]

        let image = try XCTUnwrap(DocumentRenderer.render(doc))
        let buffer = try XCTUnwrap(PixelBuffer.decode(image))
        let index = 10 * buffer.bytesPerRow + 30 * 4

        XCTAssertGreaterThan(Int(buffer.pixels[index + 1]), 150)
    }

    func test_render_annotationsDoNotChangeOutputSize() throws {
        var doc = paddedDoc(
            padding: 10,
            background: .solidColor(CGColor(red: 0, green: 0, blue: 0, alpha: 1))
        )
        let before = try XCTUnwrap(DocumentRenderer.render(doc))
        doc.annotations = [
            Annotation(
                kind: .text(
                    origin: CGPoint(x: 5, y: 5),
                    string: "Hi",
                    fontSize: 18,
                    color: CGColor(gray: 1, alpha: 1)
                )
            )
        ]
        let after = try XCTUnwrap(DocumentRenderer.render(doc))

        XCTAssertEqual(before.width, after.width)
        XCTAssertEqual(before.height, after.height)
    }

    func test_render_paddingOffsetsAnnotationWithoutMutatingIt() throws {
        var doc = paddedDoc(padding: 0, background: .none)
        let annotation = Annotation(kind: .rect(
            frame: CGRect(x: 10, y: 10, width: 12, height: 12),
            stroke: nil,
            fill: CGColor(red: 0, green: 0, blue: 1, alpha: 1),
            weight: 0,
            cornerRadius: 0
        ))
        doc.annotations = [annotation]
        doc.padding = .uniform(20)

        let image = try XCTUnwrap(DocumentRenderer.render(doc))
        let buffer = try XCTUnwrap(PixelBuffer.decode(image))
        let index = 32 * buffer.bytesPerRow + 32 * 4

        XCTAssertLessThan(Int(buffer.pixels[index]), 20)
        XCTAssertGreaterThan(Int(buffer.pixels[index + 2]), 235)
        XCTAssertEqual(doc.annotations, [annotation])
    }

    func test_render_concentricOuter_clipsCardCorners() throws {
        let doc = EditorDocument(
            screenshot: TestImage.solid(.red, size: CGSize(width: 200, height: 200)),
            viewport: CGSize(width: 200, height: 200),
            pageTitle: "t", pageURL: "u",
            baseSelection: CGRect(x: 50, y: 50, width: 80, height: 60),
            selectionCornerRadii: .uniform(14),
            padding: .uniform(10),
            background: .solidColor(CGColor(red: 0, green: 0, blue: 1, alpha: 1))
        )
        let image = try XCTUnwrap(DocumentRenderer.render(doc))
        let buffer = try XCTUnwrap(PixelBuffer.decode(image))

        // Outer corner is now rounded -> top-left pixel is outside the card -> transparent.
        XCTAssertEqual(buffer.pixels[3], 0, "concentric outer corner must be transparent")

        // Center of the padded card is still opaque background (blue).
        let cx = (buffer.width / 2)
        let cy = 5 // inside top margin band, away from corners
        let idx = cy * buffer.bytesPerRow + cx * 4
        XCTAssertEqual(Int(buffer.pixels[idx + 3]), 255, "card interior margin must stay opaque")
    }

    func test_render_rectangularShot_outerCornersUnaffected() throws {
        // No corner radii -> outer radii zero -> full-bleed background, opaque corner.
        let doc = EditorDocument(
            screenshot: TestImage.solid(.red, size: CGSize(width: 200, height: 200)),
            viewport: CGSize(width: 200, height: 200),
            pageTitle: "t", pageURL: "u",
            baseSelection: CGRect(x: 50, y: 50, width: 80, height: 60),
            selectionCornerRadii: .zero,
            padding: .uniform(10),
            background: .solidColor(CGColor(red: 0, green: 0, blue: 1, alpha: 1))
        )
        let image = try XCTUnwrap(DocumentRenderer.render(doc))
        let buffer = try XCTUnwrap(PixelBuffer.decode(image))
        XCTAssertEqual(Int(buffer.pixels[3]), 255, "rectangular shot keeps opaque corners")
    }

    func test_render_concentricOuter_clipsAnnotationsAtCardCorners() throws {
        var doc = EditorDocument(
            screenshot: TestImage.solid(.red, size: CGSize(width: 200, height: 200)),
            viewport: CGSize(width: 200, height: 200),
            pageTitle: "t", pageURL: "u",
            baseSelection: CGRect(x: 50, y: 50, width: 80, height: 60),
            selectionCornerRadii: .uniform(14),
            padding: .uniform(10),
            background: .none
        )
        doc.annotations = [
            Annotation(kind: .rect(
                // Selection-relative coordinates: -padding reaches output (0, 0).
                frame: CGRect(x: -10, y: -10, width: 20, height: 20),
                stroke: nil,
                fill: CGColor(red: 0, green: 1, blue: 0, alpha: 1),
                weight: 0,
                cornerRadius: 0
            ))
        ]

        let image = try XCTUnwrap(DocumentRenderer.render(doc))
        let buffer = try XCTUnwrap(PixelBuffer.decode(image))

        XCTAssertEqual(buffer.pixels[3], 0, "annotation content in the outer corner must be clipped")
    }

    private func paddedDoc(padding: CGFloat, background: BackgroundStyle) -> EditorDocument {
        document(
            screenshot: TestImage.solid(.red, size: CGSize(width: 200, height: 200)),
            selection: CGRect(x: 50, y: 50, width: 80, height: 60),
            padding: padding,
            background: background
        )
    }

    private func document(
        screenshot: CGImage,
        selection: CGRect,
        padding: CGFloat,
        background: BackgroundStyle
    ) -> EditorDocument {
        EditorDocument(
            screenshot: screenshot,
            viewport: CGSize(width: screenshot.width, height: screenshot.height),
            pageTitle: "t",
            pageURL: "u",
            baseSelection: selection,
            padding: PaddingConfig(top: padding, right: padding, bottom: padding, left: padding),
            background: background
        )
    }

    private func verticalSplitImage(size: CGSize) -> CGImage {
        let width = Int(size.width)
        let height = Int(size.height)
        let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
        let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
                | CGBitmapInfo.byteOrder32Big.rawValue
        )!
        context.setFillColor(CGColor(red: 1, green: 0, blue: 0, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height / 2))
        context.setFillColor(CGColor(red: 0, green: 0, blue: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: height / 2, width: width, height: height - height / 2))
        return context.makeImage()!
    }
}
