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

    func test_imageBounds_matchesFullScreenshotSize() {
        let doc = makeDoc(screenshotSize: CGSize(width: 800, height: 600))
        XCTAssertEqual(doc.imageBounds, CGRect(x: 0, y: 0, width: 800, height: 600))
    }

    func test_initialCanvasFit_centersSelectionWithViewportMargin() {
        let viewport = CGSize(width: 800, height: 600)
        let margin = CanvasCoordinator.initialViewportMargin(for: viewport)
        let selection = CGRect(x: 100, y: 120, width: 320, height: 160)
        let fit = CanvasCoordinator.initialFitRect(
            for: selection,
            in: viewport
        )
        let zoom = CanvasScrollView.fitMagnification(for: fit, in: viewport, limits: 0.05...16)
        let horizontalMargin = (viewport.width - selection.width * zoom) / 2
        let verticalMargin = (viewport.height - selection.height * zoom) / 2

        XCTAssertEqual(fit.midX, selection.midX, accuracy: 0.001)
        XCTAssertEqual(fit.midY, selection.midY, accuracy: 0.001)
        XCTAssertEqual(fit.width / fit.height, 800.0 / 600.0, accuracy: 0.001)
        XCTAssertGreaterThanOrEqual(horizontalMargin, margin - 0.001)
        XCTAssertGreaterThanOrEqual(verticalMargin, margin - 0.001)
        XCTAssertEqual(min(horizontalMargin, verticalMargin), margin, accuracy: 0.001)

        let tallSelection = CGRect(x: 120, y: 80, width: 120, height: 300)
        let tallFit = CanvasCoordinator.initialFitRect(
            for: tallSelection,
            in: viewport
        )
        let tallZoom = CanvasScrollView.fitMagnification(for: tallFit, in: viewport, limits: 0.05...16)
        let tallHorizontalMargin = (viewport.width - tallSelection.width * tallZoom) / 2
        let tallVerticalMargin = (viewport.height - tallSelection.height * tallZoom) / 2

        XCTAssertEqual(tallFit.midX, tallSelection.midX, accuracy: 0.001)
        XCTAssertEqual(tallFit.midY, tallSelection.midY, accuracy: 0.001)
        XCTAssertEqual(tallFit.width / tallFit.height, 800.0 / 600.0, accuracy: 0.001)
        XCTAssertGreaterThanOrEqual(tallHorizontalMargin, margin - 0.001)
        XCTAssertGreaterThanOrEqual(tallVerticalMargin, margin - 0.001)
        XCTAssertEqual(min(tallHorizontalMargin, tallVerticalMargin), margin, accuracy: 0.001)
    }

    func test_initialCanvasFit_adaptsMarginForCompactViewport() {
        let viewport = CGSize(width: 240, height: 160)
        let margin = CanvasCoordinator.initialViewportMargin(for: viewport)
        let selection = CGRect(x: 100, y: 120, width: 80, height: 80)
        let fit = CanvasCoordinator.initialFitRect(for: selection, in: viewport)
        let zoom = CanvasScrollView.fitMagnification(for: fit, in: viewport, limits: 0.05...16)
        let horizontalMargin = (viewport.width - selection.width * zoom) / 2
        let verticalMargin = (viewport.height - selection.height * zoom) / 2

        XCTAssertLessThan(margin, 96)
        XCTAssertLessThan(margin * 2, min(viewport.width, viewport.height))
        XCTAssertGreaterThanOrEqual(horizontalMargin, margin - 0.001)
        XCTAssertGreaterThanOrEqual(verticalMargin, margin - 0.001)
    }

    func test_initialCanvasPlacement_expandsCanvasToCenterEdgeSelection() {
        let imageBounds = CGRect(x: 0, y: 0, width: 1000, height: 1000)
        let selection = CGRect(x: 0, y: 0, width: 100, height: 100)
        let fit = CanvasCoordinator.initialFitRect(
            for: selection,
            in: CGSize(width: 800, height: 600)
        )
        let placement = CanvasInitialPlacement(imageBounds: imageBounds, targetRect: fit)

        XCTAssertGreaterThan(placement.imageFrame.minX, 0)
        XCTAssertGreaterThan(placement.imageFrame.minY, 0)
        XCTAssertEqual(
            placement.targetRect.midX,
            placement.imageFrame.minX + selection.midX,
            accuracy: 0.001
        )
        XCTAssertEqual(
            placement.targetRect.midY,
            placement.imageFrame.minY + selection.midY,
            accuracy: 0.001
        )
    }

    func test_initialCanvasPlacement_keepsSelectionCenterInCanvasCoordinatesForEveryEdge() {
        let imageBounds = CGRect(x: 0, y: 0, width: 1000, height: 800)
        let selections = [
            CGRect(x: 0, y: 0, width: 100, height: 80),
            CGRect(x: 900, y: 0, width: 100, height: 80),
            CGRect(x: 0, y: 720, width: 100, height: 80),
            CGRect(x: 900, y: 720, width: 100, height: 80)
        ]

        for selection in selections {
            let fit = CanvasCoordinator.initialFitRect(
                for: selection,
                in: CGSize(width: 800, height: 600)
            )
            let placement = CanvasInitialPlacement(imageBounds: imageBounds, targetRect: fit)

            XCTAssertEqual(
                placement.targetRect.midX,
                placement.imageFrame.minX + selection.midX,
                accuracy: 0.001
            )
            XCTAssertEqual(
                placement.targetRect.midY,
                placement.imageFrame.minY + selection.midY,
                accuracy: 0.001
            )
        }
    }

    func test_canvasScrollViewFitMagnificationUsesLimitingAxis() {
        XCTAssertEqual(
            CanvasScrollView.fitMagnification(
                for: CGRect(x: 0, y: 0, width: 400, height: 100),
                in: CGSize(width: 800, height: 600),
                limits: 0.05...16
            ),
            2,
            accuracy: 0.001
        )
        XCTAssertEqual(
            CanvasScrollView.fitMagnification(
                for: CGRect(x: 0, y: 0, width: 100, height: 400),
                in: CGSize(width: 800, height: 600),
                limits: 0.05...16
            ),
            1.5,
            accuracy: 0.001
        )
    }

    @MainActor
    func test_canvasDocumentCoordinatesMatchCanvasContentCoordinates() {
        let container = CanvasDocumentView(frame: CGRect(x: 0, y: 0, width: 1000, height: 800))
        let content = CanvasContentView(frame: CGRect(x: 20, y: 30, width: 400, height: 300))
        container.addSubview(content)

        let pointInContainer = content.convert(CGPoint(x: 100, y: 120), to: container)

        XCTAssertEqual(pointInContainer.x, 120, accuracy: 0.001)
        XCTAssertEqual(pointInContainer.y, 150, accuracy: 0.001)
    }

    @MainActor
    func test_canvasScrollViewKeepsScrollerChromeOutOfTheCanvasCenteringMath() {
        let scrollView = CanvasScrollView(frame: CGRect(x: 0, y: 0, width: 800, height: 600))

        XCTAssertFalse(scrollView.hasHorizontalScroller)
        XCTAssertFalse(scrollView.hasVerticalScroller)
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
