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

    func test_render_v0_pixelEqualToLegacyCaptureCrop() throws {
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
            sourceTitle: "Fractional",
            sourceURL: "https://example.com",
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
        var doc = paddedDoc(padding: 10, background: .none)
        doc.shadow.isEnabled = false  // isolate background fill from the card's (default-on) drop shadow
        let image = try XCTUnwrap(DocumentRenderer.render(doc))
        let buffer = try XCTUnwrap(PixelBuffer.decode(image))
        XCTAssertEqual(buffer.pixels[3], 0, "top-left margin alpha must be 0 for .none")
    }

    func test_render_selectionCornerRadiiMasksScreenshotCorners() throws {
        let doc = EditorDocument(
            screenshot: TestImage.solid(.red, size: CGSize(width: 48, height: 48)),
            viewport: CGSize(width: 48, height: 48),
            sourceTitle: "Rounded",
            sourceURL: "https://example.com",
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
            sourceTitle: "Rounded",
            sourceURL: "https://example.com",
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

    func test_render_arrow_overridesScreenshotPixels() throws {
        var doc = paddedDoc(padding: 0, background: .none)
        doc.annotations = [
            Annotation(
                kind: .arrow(
                    from: CGPoint(x: 5, y: 5),
                    to: CGPoint(x: 70, y: 50),
                    pathStyle: .straight,
                    curve: nil,
                    color: CGColor(red: 0, green: 0, blue: 1, alpha: 1),
                    weight: 8,
                    borderColor: nil
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

    func test_render_windowCard_clipsCardCorners() throws {
        let doc = EditorDocument(
            screenshot: TestImage.solid(.red, size: CGSize(width: 200, height: 200)),
            viewport: CGSize(width: 200, height: 200),
            sourceTitle: "t", sourceURL: "u",
            baseSelection: CGRect(x: 50, y: 50, width: 80, height: 60),
            selectionCornerRadii: .uniform(14),
            padding: .uniform(10),
            background: .solidColor(CGColor(red: 0, green: 0, blue: 1, alpha: 1))
        )
        let image = try XCTUnwrap(DocumentRenderer.render(doc))
        let buffer = try XCTUnwrap(PixelBuffer.decode(image))

        // Card rounds to the window radius -> top-left pixel is outside the card -> transparent.
        XCTAssertEqual(buffer.pixels[3], 0, "rounded card outer corner must be transparent")

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
            sourceTitle: "t", sourceURL: "u",
            baseSelection: CGRect(x: 50, y: 50, width: 80, height: 60),
            selectionCornerRadii: .zero,
            padding: .uniform(10),
            background: .solidColor(CGColor(red: 0, green: 0, blue: 1, alpha: 1))
        )
        let image = try XCTUnwrap(DocumentRenderer.render(doc))
        let buffer = try XCTUnwrap(PixelBuffer.decode(image))
        XCTAssertEqual(Int(buffer.pixels[3]), 255, "rectangular shot keeps opaque corners")
    }

    func test_render_dynamicBackground_marginIsOpaque() throws {
        let image = try XCTUnwrap(DocumentRenderer.render(paddedDoc(padding: 20, background: .dynamic)))
        let buf = try XCTUnwrap(PixelBuffer.decode(image))
        XCTAssertEqual(Int(buf.pixels[3]), 255, "dynamic background margin must be opaque")
    }

    func test_render_dynamicBackground_seamApproximatesEdgeColor() throws {
        let solid = FixtureDocument.makeSolidImage(
            color: CGColor(srgbRed: 0.85, green: 0.2, blue: 0.2, alpha: 1),
            size: CGSize(width: 60, height: 60))
        let doc = document(
            screenshot: solid,
            selection: CGRect(x: 0, y: 0, width: 60, height: 60),
            padding: 24,
            background: .dynamic
        )
        let image = try XCTUnwrap(DocumentRenderer.render(doc))
        let buf = try XCTUnwrap(PixelBuffer.decode(image))
        let i = (6 * buf.bytesPerRow) + 6 * 4
        XCTAssertGreaterThan(Int(buf.pixels[i + 0]), Int(buf.pixels[i + 1]) + 30)
        XCTAssertGreaterThan(Int(buf.pixels[i + 0]), Int(buf.pixels[i + 2]) + 30)
    }

    func test_render_windowCard_clipsAnnotationsAtCardCorners() throws {
        var doc = EditorDocument(
            screenshot: TestImage.solid(.red, size: CGSize(width: 200, height: 200)),
            viewport: CGSize(width: 200, height: 200),
            sourceTitle: "t", sourceURL: "u",
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

    /// A solid-color image with transparent rounded corners baked into its
    /// alpha, mimicking a native window capture.
    private func roundedAlphaImage(size: CGSize, radius: CGFloat, color: CGColor) -> CGImage {
        let w = Int(size.width), h = Int(size.height)
        let ctx = CGContext(
            data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue
        )!
        let rect = CGRect(x: 0, y: 0, width: w, height: h)
        ctx.addPath(SelectionCornerRadii.uniform(radius).path(in: rect))
        ctx.clip()
        ctx.setFillColor(color)
        ctx.fill(rect)
        return ctx.makeImage()!
    }

    func test_render_nativeBakedCorners_cardRoundsToWindowRadius() throws {
        let shot = roundedAlphaImage(size: CGSize(width: 120, height: 120), radius: 16,
                                     color: CGColor(red: 1, green: 0, blue: 0, alpha: 1))
        let doc = EditorDocument(
            screenshot: shot,
            viewport: CGSize(width: 120, height: 120),
            sourceTitle: "t", sourceURL: "u",
            baseSelection: CGRect(x: 0, y: 0, width: 120, height: 120),
            selectionCornerRadii: .zero,            // native: corners baked, no mask
            contentCornerRadii: .uniform(16),       // measured visual radius
            padding: .uniform(20),
            background: .solidColor(CGColor(red: 0, green: 0, blue: 1, alpha: 1))
        )
        let image = try XCTUnwrap(DocumentRenderer.render(doc))
        let buffer = try XCTUnwrap(PixelBuffer.decode(image))

        // Card rounds to the window radius -> top-left pixel transparent.
        XCTAssertEqual(Int(buffer.pixels[3]), 0, "card must round the outer corner")

        // Mid top edge, inside the padding band -> opaque blue background.
        let cx = buffer.width / 2
        let idx = 4 * buffer.bytesPerRow + cx * 4
        XCTAssertEqual(Int(buffer.pixels[idx + 3]), 255, "padding band must be opaque")
        XCTAssertGreaterThan(Int(buffer.pixels[idx + 2]), 200, "padding band is the blue background")
    }

    // MARK: - Background effects / shadow / screenshot corners

    func test_render_withBackgroundEffects_outputSizeUnchanged() throws {
        let plain = try XCTUnwrap(DocumentRenderer.render(paddedDoc(padding: 20, background: .dynamic)))
        var doc = paddedDoc(padding: 20, background: .dynamic)
        doc.backgroundEffects = BackgroundEffects(blurRadius: 8, noiseOpacity: 0.2)
        let withFx = try XCTUnwrap(DocumentRenderer.render(doc))
        XCTAssertEqual(plain.width, withFx.width)
        XCTAssertEqual(plain.height, withFx.height)
    }

    func test_composedBackgroundImage_matchesCropSize() throws {
        var doc = paddedDoc(padding: 20, background: .solidColor(CGColor(red: 0, green: 0, blue: 1, alpha: 1)))
        doc.backgroundEffects = BackgroundEffects(blurRadius: 0, noiseOpacity: 0.3)
        let image = try XCTUnwrap(DocumentRenderer.composedBackgroundImage(for: doc))
        let crop = doc.effectiveCrop.integral
        XCTAssertEqual(image.width, Int(crop.width))
        XCTAssertEqual(image.height, Int(crop.height))
    }

    func test_render_blurredNoisyMargin_staysOpaque() throws {
        var doc = paddedDoc(padding: 20, background: .solidColor(CGColor(red: 0, green: 0, blue: 1, alpha: 1)))
        doc.backgroundEffects = BackgroundEffects(blurRadius: 6, noiseOpacity: 0.15)
        let image = try XCTUnwrap(DocumentRenderer.render(doc))
        let buffer = try XCTUnwrap(PixelBuffer.decode(image))
        XCTAssertEqual(Int(buffer.pixels[3]), 255, "blurred + noisy solid margin must stay opaque")
    }

    func test_composedBackground_noisePreservesSolidHue() throws {
        let baseDoc = paddedDoc(
            padding: 20,
            background: .solidColor(CGColor(red: 0, green: 0, blue: 1, alpha: 1))
        )
        var doc = baseDoc
        doc.backgroundEffects = BackgroundEffects(blurRadius: 0, noiseOpacity: 0.30)

        let baseImage = try XCTUnwrap(DocumentRenderer.composedBackgroundImage(for: baseDoc))
        let image = try XCTUnwrap(DocumentRenderer.composedBackgroundImage(for: doc))
        let baseAverages = averageRGB(try XCTUnwrap(PixelBuffer.decode(baseImage)))
        let buffer = try XCTUnwrap(PixelBuffer.decode(image))
        let averages = averageRGB(buffer)
        let baseHSV = hsv(baseAverages)
        let noisyHSV = hsv(averages)

        XCTAssertEqual(noisyHSV.hue, baseHSV.hue, accuracy: 0.015)
        XCTAssertEqual(noisyHSV.saturation, baseHSV.saturation, accuracy: 0.04)
    }

    func test_composedBackground_noiseIsSubtleMaterialGrain() throws {
        var doc = paddedDoc(
            padding: 20,
            background: .solidColor(CGColor(gray: 0.45, alpha: 1))
        )
        doc.backgroundEffects = BackgroundEffects(blurRadius: 0, noiseOpacity: 0.20)

        let buffer = try XCTUnwrap(PixelBuffer.decode(
            try XCTUnwrap(DocumentRenderer.composedBackgroundImage(for: doc))
        ))
        let averageDelta = averageHorizontalLuminanceDelta(buffer)
        let maxDelta = maximumHorizontalLuminanceDelta(buffer)

        XCTAssertGreaterThan(averageDelta, 0.35, "noise should remain visible as material grain")
        XCTAssertLessThan(maxDelta, 28, "grain should avoid harsh single-pixel contrast spikes")
    }

    func test_composedBackground_blurSoftensNoise() throws {
        var sharpDoc = paddedDoc(
            padding: 20,
            background: .solidColor(CGColor(gray: 0.5, alpha: 1))
        )
        sharpDoc.backgroundEffects = BackgroundEffects(blurRadius: 0, noiseOpacity: 0.30)
        var blurredDoc = sharpDoc
        blurredDoc.backgroundEffects.blurRadius = 12

        let sharp = try XCTUnwrap(PixelBuffer.decode(
            try XCTUnwrap(DocumentRenderer.composedBackgroundImage(for: sharpDoc))
        ))
        let blurred = try XCTUnwrap(PixelBuffer.decode(
            try XCTUnwrap(DocumentRenderer.composedBackgroundImage(for: blurredDoc))
        ))

        XCTAssertLessThan(
            averageHorizontalLuminanceDelta(blurred),
            averageHorizontalLuminanceDelta(sharp) * 0.5,
            "blur must soften the complete background, including its noise"
        )
    }

    func test_render_shadowVisibleOutsideRoundedScreenshotWithNoise() throws {
        var doc = EditorDocument(
            screenshot: TestImage.solid(.red, size: CGSize(width: 80, height: 80)),
            viewport: CGSize(width: 80, height: 80),
            sourceTitle: "Shadow",
            sourceURL: "https://example.com",
            baseSelection: CGRect(x: 20, y: 20, width: 40, height: 40),
            selectionCornerRadii: .uniform(12),
            padding: .uniform(20),
            background: .solidColor(CGColor(gray: 1, alpha: 1))
        )
        doc.backgroundEffects = BackgroundEffects(blurRadius: 0, noiseOpacity: 0.10)
        doc.shadow = ShadowConfig(
            isEnabled: true,
            blur: 12,
            offsetX: 0,
            offsetY: 0,
            opacity: 1,
            color: CGColor(gray: 0, alpha: 1)
        )

        let image = try XCTUnwrap(DocumentRenderer.render(doc))
        let buffer = try XCTUnwrap(PixelBuffer.decode(image))
        let leftShadowBand = averageLuminance(
            buffer,
            xRange: 17..<20,
            yRange: 28..<52
        )
        let surroundingBackground = averageLuminance(
            buffer,
            xRange: 0..<8,
            yRange: 24..<56
        )

        XCTAssertLessThan(
            leftShadowBand,
            surroundingBackground - 8,
            "rounded screenshot shadow must remain visibly darker than its noisy background"
        )
    }

    func test_render_shadowDisabled_rendersAtCropSize() throws {
        var doc = paddedDoc(padding: 20, background: .solidColor(CGColor(red: 0, green: 0, blue: 1, alpha: 1)))
        doc.shadow.isEnabled = false
        let image = try XCTUnwrap(DocumentRenderer.render(doc))
        XCTAssertEqual(image.width, 120)
        XCTAssertEqual(image.height, 100)
    }

    func test_render_screenshotCornerOverride_roundsScreenshot() throws {
        var doc = EditorDocument(
            screenshot: TestImage.solid(.red, size: CGSize(width: 48, height: 48)),
            viewport: CGSize(width: 48, height: 48),
            sourceTitle: "Rounded",
            sourceURL: "https://example.com",
            baseSelection: CGRect(x: 4, y: 4, width: 40, height: 40),
            background: .none
        )
        doc.screenshotCornerOverride = 14
        let image = try XCTUnwrap(DocumentRenderer.render(doc))
        let buffer = try XCTUnwrap(PixelBuffer.decode(image))
        XCTAssertEqual(buffer.pixels[3], 0, "overridden screenshot corner must be transparent")
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
            sourceTitle: "t",
            sourceURL: "u",
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

    private func averageRGB(_ buffer: PixelBuffer.Buffer) -> (red: Double, green: Double, blue: Double) {
        var red = 0.0
        var green = 0.0
        var blue = 0.0
        let count = Double(buffer.width * buffer.height)
        for y in 0..<buffer.height {
            for x in 0..<buffer.width {
                let index = y * buffer.bytesPerRow + x * 4
                red += Double(buffer.pixels[index])
                green += Double(buffer.pixels[index + 1])
                blue += Double(buffer.pixels[index + 2])
            }
        }
        return (red / count, green / count, blue / count)
    }

    private func hsv(
        _ rgb: (red: Double, green: Double, blue: Double)
    ) -> (hue: Double, saturation: Double, value: Double) {
        let red = rgb.red / 255
        let green = rgb.green / 255
        let blue = rgb.blue / 255
        let maximum = max(red, green, blue)
        let minimum = min(red, green, blue)
        let delta = maximum - minimum
        let hue: Double
        if delta == 0 {
            hue = 0
        } else if maximum == red {
            hue = ((green - blue) / delta).truncatingRemainder(dividingBy: 6) / 6
        } else if maximum == green {
            hue = (((blue - red) / delta) + 2) / 6
        } else {
            hue = (((red - green) / delta) + 4) / 6
        }
        let normalizedHue = hue < 0 ? hue + 1 : hue
        let saturation = maximum == 0 ? 0 : delta / maximum
        return (normalizedHue, saturation, maximum)
    }

    private func averageHorizontalLuminanceDelta(_ buffer: PixelBuffer.Buffer) -> Double {
        var total = 0.0
        var count = 0
        for y in 0..<buffer.height {
            for x in 1..<buffer.width {
                let previous = y * buffer.bytesPerRow + (x - 1) * 4
                let current = y * buffer.bytesPerRow + x * 4
                total += abs(luminance(buffer.pixels, at: current) - luminance(buffer.pixels, at: previous))
                count += 1
            }
        }
        return total / Double(max(1, count))
    }

    private func maximumHorizontalLuminanceDelta(_ buffer: PixelBuffer.Buffer) -> Double {
        var maximum = 0.0
        for y in 0..<buffer.height {
            for x in 1..<buffer.width {
                let previous = y * buffer.bytesPerRow + (x - 1) * 4
                let current = y * buffer.bytesPerRow + x * 4
                maximum = max(
                    maximum,
                    abs(luminance(buffer.pixels, at: current) - luminance(buffer.pixels, at: previous))
                )
            }
        }
        return maximum
    }

    private func averageLuminance(
        _ buffer: PixelBuffer.Buffer,
        xRange: Range<Int>,
        yRange: Range<Int>
    ) -> Double {
        var total = 0.0
        var count = 0
        for y in yRange {
            for x in xRange {
                total += luminance(buffer.pixels, at: y * buffer.bytesPerRow + x * 4)
                count += 1
            }
        }
        return total / Double(max(1, count))
    }

    private func luminance(_ pixels: Data, at index: Int) -> Double {
        0.2126 * Double(pixels[index])
            + 0.7152 * Double(pixels[index + 1])
            + 0.0722 * Double(pixels[index + 2])
    }
}
