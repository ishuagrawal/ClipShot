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
            sourceTitle: "Test",
            sourceURL: "https://example.com",
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

    func test_fitFocusRect_withoutBackground_framesScreenshotNotPaddedCard() {
        let doc = makeDoc(padding: .uniform(40))
        XCTAssertEqual(doc.fitFocusRect, doc.baseSelection)
    }

    func test_fitFocusRect_withBackground_framesPaddedCard() {
        var doc = makeDoc(padding: .uniform(40))
        doc.background = .defaultGradient
        XCTAssertEqual(doc.fitFocusRect, doc.effectiveCrop)
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

    func test_concentricOuter_uniformInnerAndPadding_growsEveryCornerByPad() {
        let inner = SelectionCornerRadii.uniform(14)
        let outer = inner.concentricOuter(padding: .uniform(10))
        XCTAssertEqual(outer, .uniform(24))
    }

    func test_concentricOuter_zeroInner_staysZero() {
        let outer = SelectionCornerRadii.zero.concentricOuter(padding: .uniform(10))
        XCTAssertTrue(outer.isZero)
    }

    func test_concentricOuter_nonUniformPadding_growsByAdjacentSides() {
        let inner = SelectionCornerRadii.uniform(10)
        let pad = PaddingConfig(top: 4, right: 6, bottom: 8, left: 2)
        let outer = inner.concentricOuter(padding: pad)
        XCTAssertEqual(outer.topLeft, CGSize(width: 12, height: 14))     // +left, +top
        XCTAssertEqual(outer.topRight, CGSize(width: 16, height: 14))    // +right, +top
        XCTAssertEqual(outer.bottomRight, CGSize(width: 16, height: 18)) // +right, +bottom
        XCTAssertEqual(outer.bottomLeft, CGSize(width: 12, height: 18))  // +left, +bottom
    }

    func test_concentricOuter_squareCornerStaysSquare() {
        let inner = SelectionCornerRadii(
            topLeft: CGSize(width: 10, height: 10),
            topRight: .zero,
            bottomRight: CGSize(width: 10, height: 10),
            bottomLeft: CGSize(width: 10, height: 10)
        )
        let outer = inner.concentricOuter(padding: .uniform(5))
        XCTAssertEqual(outer.topRight, .zero, "a square corner must not become rounded")
        XCTAssertEqual(outer.topLeft, CGSize(width: 15, height: 15))
    }

    private func roundedDoc(padding: PaddingConfig, radius: CGFloat) -> EditorDocument {
        EditorDocument(
            screenshot: TestImage.solid(.red, size: CGSize(width: 400, height: 400)),
            viewport: CGSize(width: 400, height: 400),
            sourceTitle: "t", sourceURL: "u",
            baseSelection: CGRect(x: 50, y: 50, width: 200, height: 160),
            selectionCornerRadii: .uniform(radius),
            padding: padding
        )
    }

    func test_outerCornerRadii_zeroPadding_isZero() {
        XCTAssertTrue(roundedDoc(padding: .zero, radius: 18).outerCornerRadii.isZero)
    }

    func test_outerCornerRadii_zeroInnerRadius_isZero() {
        let doc = EditorDocument(
            screenshot: TestImage.solid(.red, size: CGSize(width: 400, height: 400)),
            viewport: CGSize(width: 400, height: 400),
            sourceTitle: "t", sourceURL: "u",
            baseSelection: CGRect(x: 50, y: 50, width: 200, height: 160),
            selectionCornerRadii: .zero,
            padding: .uniform(10)
        )
        XCTAssertTrue(doc.outerCornerRadii.isZero)
    }

    func test_outerCornerRadii_rounded_isConcentric() {
        let doc = roundedDoc(padding: .uniform(10), radius: 18)
        XCTAssertEqual(doc.outerCornerRadii, .uniform(28))
    }

    func test_autoSweetSpot_midRange_isSixPercentOfMaxSide() {
        let pad = PaddingConfig.autoSweetSpot(forSelection: CGSize(width: 1440, height: 900))
        XCTAssertEqual(pad, .uniform(86)) // round(0.06 * 1440) = 86
    }

    func test_autoSweetSpot_smallImage_clampsToFloor() {
        let pad = PaddingConfig.autoSweetSpot(forSelection: CGSize(width: 300, height: 200))
        XCTAssertEqual(pad, .uniform(40)) // round(18) -> floor 40
    }

    func test_autoSweetSpot_hugeImage_clampsToCeiling() {
        let pad = PaddingConfig.autoSweetSpot(forSelection: CGSize(width: 4000, height: 3000))
        XCTAssertEqual(pad, .uniform(200)) // round(240) -> ceiling 200
    }

    func test_autoSweetSpot_isUniform() {
        let pad = PaddingConfig.autoSweetSpot(forSelection: CGSize(width: 1000, height: 700))
        XCTAssertNotNil(pad.uniform)
    }

    func test_outerCornerRadii_premaskedCorners_isConcentricEvenWithZeroSelectionMask() {
        // Native window capture: corners baked into pixels, selectionCornerRadii is zero,
        // but the shot still has a visual corner radius carried by contentCornerRadii.
        let doc = EditorDocument(
            screenshot: TestImage.solid(.red, size: CGSize(width: 400, height: 400)),
            viewport: CGSize(width: 400, height: 400),
            sourceTitle: "t", sourceURL: "u",
            baseSelection: CGRect(x: 50, y: 50, width: 200, height: 160),
            selectionCornerRadii: .zero,
            contentCornerRadii: .uniform(18),
            padding: .uniform(10)
        )
        XCTAssertEqual(doc.outerCornerRadii, .uniform(28))
    }

    func test_contentCornerRadii_defaultsToSelectionCornerRadii() {
        let doc = EditorDocument(
            screenshot: TestImage.solid(.red, size: CGSize(width: 400, height: 400)),
            viewport: CGSize(width: 400, height: 400),
            sourceTitle: "t", sourceURL: "u",
            baseSelection: CGRect(x: 50, y: 50, width: 200, height: 160),
            selectionCornerRadii: .uniform(12),
            padding: .uniform(10)
        )
        XCTAssertEqual(doc.outerCornerRadii.isZero, false)
    }

    func test_cardCornerRadius_autoModeMatchesScreenshotRadius() {
        let doc = EditorDocument(
            screenshot: TestImage.solid(.red, size: CGSize(width: 400, height: 400)),
            viewport: CGSize(width: 400, height: 400),
            sourceTitle: "t", sourceURL: "u",
            baseSelection: CGRect(x: 50, y: 50, width: 200, height: 160),
            selectionCornerRadii: .zero,
            contentCornerRadii: .uniform(18),
            padding: .uniform(40)
        )
        XCTAssertEqual(doc.cardCornerRadius, 18)
    }

    func test_cardCornerRadius_nilWithoutPaddingOrRadius() {
        let noPad = EditorDocument(
            screenshot: TestImage.solid(.red, size: CGSize(width: 400, height: 400)),
            viewport: CGSize(width: 400, height: 400),
            sourceTitle: "t", sourceURL: "u",
            baseSelection: CGRect(x: 50, y: 50, width: 200, height: 160),
            contentCornerRadii: .uniform(18),
            padding: .zero
        )
        XCTAssertNil(noPad.cardCornerRadius)
    }

    private func overrideDoc(_ override: CGFloat?) -> EditorDocument {
        EditorDocument(
            screenshot: TestImage.solid(.red, size: CGSize(width: 400, height: 400)),
            viewport: CGSize(width: 400, height: 400),
            sourceTitle: "t", sourceURL: "u",
            baseSelection: CGRect(x: 50, y: 50, width: 200, height: 160),
            selectionCornerRadii: .zero,
            contentCornerRadii: .uniform(18),
            padding: .uniform(40),
            cardCornerOverride: override
        )
    }

    func test_cardCornerRadius_usesOverrideWhenSet() {
        XCTAssertEqual(overrideDoc(60).cardCornerRadius, 60)
    }

    func test_cardCornerRadius_overrideZeroGivesSquareCard() {
        XCTAssertEqual(overrideDoc(0).cardCornerRadius, 0)
    }

    func test_cardCornerRadius_overrideClampedToHalfMinDimension() {
        // effectiveCrop is 280×240, so max radius is 120.
        XCTAssertEqual(overrideDoc(9999).cardCornerRadius, 120)
    }

    func test_cardCornerRadius_nilOverrideFallsBackToConcentric() {
        XCTAssertEqual(overrideDoc(nil).cardCornerRadius, 18)
    }

    func test_outerCornerRadii_suppressedWhenOverrideSet() {
        // Override is uniform (rendered via cardCornerRadius); the bezier outer
        // path must yield so override 0 actually produces a square card.
        XCTAssertTrue(overrideDoc(0).outerCornerRadii.isZero)
        XCTAssertTrue(overrideDoc(60).outerCornerRadii.isZero)
        XCTAssertFalse(overrideDoc(nil).outerCornerRadii.isZero)
    }

    func test_autoCardCornerRadius_ignoresOverride() {
        // Auto value is the derived concentric radius regardless of override.
        XCTAssertEqual(overrideDoc(60).autoCardCornerRadius, 18)
        XCTAssertEqual(overrideDoc(nil).autoCardCornerRadius, 18)
    }

    func test_isCardCornerConcentric_whenManualOuterMatchesRenderedInner() {
        var doc = overrideDoc(18)
        XCTAssertTrue(doc.isCardCornerConcentric)

        doc.cardCornerOverride = 19
        XCTAssertFalse(doc.isCardCornerConcentric)
    }

    func test_isCardCornerConcentric_whenCornersAreLockedTogether() {
        var doc = overrideDoc(50)
        doc.lockCornersToCard = true
        XCTAssertTrue(doc.isCardCornerConcentric)
    }

    // MARK: - Shadow / background effects / screenshot corners

    func test_shadowConfig_defaultIsEnabledSoftBlack() {
        XCTAssertTrue(ShadowConfig.default.isEnabled)
        XCTAssertEqual(ShadowConfig.default.opacity, 0.30, accuracy: 0.0001)
        XCTAssertEqual(ShadowConfig.default.blur, 30)
    }

    func test_backgroundEffects_isActiveOnlyWhenBlurOrNoise() {
        XCTAssertFalse(BackgroundEffects.none.isActive)
        XCTAssertTrue(BackgroundEffects(blurRadius: 2, noiseOpacity: 0).isActive)
        XCTAssertTrue(BackgroundEffects(blurRadius: 0, noiseOpacity: 0.1).isActive)
    }

    func test_document_defaults_shadowEnabled_noEffects_noCornerOverride() {
        let doc = makeDoc()
        XCTAssertTrue(doc.shadow.isEnabled)
        XCTAssertFalse(doc.backgroundEffects.isActive)
        XCTAssertNil(doc.screenshotCornerOverride)
        XCTAssertFalse(doc.lockCornersToCard)
    }

    func test_screenshotCornerOverride_drivesEffectiveSelectionRadii() {
        var doc = roundedDoc(padding: .zero, radius: 0)
        XCTAssertEqual(doc.effectiveSelectionCornerRadii.uniformRadius, nil)
        doc.screenshotCornerOverride = 24
        XCTAssertEqual(doc.effectiveSelectionCornerRadii.uniformRadius, 24)
    }

    func test_screenshotCornerOverride_drivesConcentricOuter() {
        var doc = roundedDoc(padding: .uniform(10), radius: 0)
        XCTAssertTrue(doc.outerCornerRadii.isZero, "no captured radius → no concentric card")
        doc.screenshotCornerOverride = 18
        XCTAssertEqual(doc.outerCornerRadii, .uniform(28)) // 18 + 10
        XCTAssertEqual(doc.autoCardCornerRadius, 18)
    }

    func test_lockCornersToCard_mirrorsCardRadius() {
        var doc = overrideDoc(50) // cardCornerOverride 50, padding 40
        XCTAssertEqual(doc.cardCornerRadius, 50)
        doc.lockCornersToCard = true
        XCTAssertEqual(doc.effectiveSelectionCornerRadii.uniformRadius, 50)
    }

    func test_version_bumpsForShadowEffectsAndCornerFields() {
        var doc = makeDoc()
        let v0 = doc.version
        doc.shadow = .default
        doc.backgroundEffects = BackgroundEffects(blurRadius: 5, noiseOpacity: 0)
        doc.screenshotCornerOverride = 10
        doc.lockCornersToCard = true
        XCTAssertEqual(doc.version, v0 + 4)
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
