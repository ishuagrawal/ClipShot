import AppKit
import CoreImage

/// Hosts the selected region of the screenshot at 1:1 pixel size. The surrounding
/// page is not drawn — only the selection layer is visible. The
/// full screenshot stays in `EditorDocument.screenshot` for tools that need it.
final class CanvasContentView: NSView {

    var document: EditorDocument? {
        didSet { updateFrameAndLayers(previous: oldValue) }
    }

    /// Fires when the visible card background for the current document has been
    /// committed on screen — synchronously for solid/gradient, on the async
    /// landing for image/dynamic/blur. The ambient glow swaps off this so the
    /// light never recolors ahead of the background it radiates.
    var onBackgroundLanded: ((CanvasBackgroundLanding) -> Void)?

    private let solidBackgroundLayer: CALayer
    private let gradientBackgroundLayer: CAGradientLayer
    private let dynamicBackgroundLayer: CALayer
    /// Oversized child of `dynamicBackgroundLayer` holding the unblurred base, so
    /// the live-blur gaussian samples real edge pixels (parent clips the overflow).
    private let blurContentLayer: CALayer
    /// Overscan per side, in points. Sized for ~3σ of the widest gaussian.
    static let liveBlurMargin: CGFloat = (BackgroundEffects.maximumBlurRadius * 3).rounded(.up)
    private let noiseBackgroundLayer: CALayer
    /// Shadow host. Never clips, so its drop shadow survives rounded corners.
    private let selectionLayer: CALayer
    /// Child of `selectionLayer` holding the screenshot and the corner clip.
    private let selectionContentLayer: CALayer
    private let selectionMaskLayer: CAShapeLayer
    private let composedBackgroundQueue: OperationQueue
    private var pendingDynamicSource: CGImage?
    private var pendingDynamicSelection: CGRect = .null
    private var pendingBGToken: BackgroundToken?
    private var pendingBGOperation: Operation?
    /// Last radius applied to `blurContentLayer.filters`; -1 when blur is off.
    private var liveBlurRadius: CGFloat = -1

    /// Identity of a composed (blur/noise) background render in flight.
    private struct BackgroundToken: Equatable {
        let screenshot: ObjectIdentifier
        let selection: CGRect
        let style: ClipShot.BackgroundStyle
        let effects: BackgroundEffects
        let size: CGSize
    }

    override init(frame frameRect: NSRect) {
        self.solidBackgroundLayer = CALayer()
        self.gradientBackgroundLayer = CAGradientLayer()
        self.dynamicBackgroundLayer = CALayer()
        self.blurContentLayer = CALayer()
        self.noiseBackgroundLayer = CALayer()
        self.selectionLayer = CALayer()
        self.selectionContentLayer = CALayer()
        self.selectionMaskLayer = CAShapeLayer()
        self.composedBackgroundQueue = OperationQueue()
        super.init(frame: frameRect)
        composedBackgroundQueue.name = "com.ishu.ClipShot.composed-background"
        composedBackgroundQueue.maxConcurrentOperationCount = 1
        composedBackgroundQueue.qualityOfService = .userInitiated
        wantsLayer = true
        layer?.backgroundColor = .clear
        layer?.masksToBounds = false

        dynamicBackgroundLayer.contentsGravity = .resize
        dynamicBackgroundLayer.magnificationFilter = .trilinear
        dynamicBackgroundLayer.minificationFilter = .trilinear
        blurContentLayer.contentsGravity = .resize
        blurContentLayer.magnificationFilter = .trilinear
        blurContentLayer.minificationFilter = .trilinear
        blurContentLayer.isHidden = true
        dynamicBackgroundLayer.addSublayer(blurContentLayer)
        selectionLayer.masksToBounds = false
        selectionContentLayer.contentsGravity = .resize
        selectionContentLayer.magnificationFilter = .trilinear
        selectionContentLayer.minificationFilter = .trilinear
        selectionLayer.addSublayer(selectionContentLayer)
        noiseBackgroundLayer.contents = Self.noiseTexture
        noiseBackgroundLayer.contentsGravity = .resize
        noiseBackgroundLayer.magnificationFilter = .linear
        noiseBackgroundLayer.minificationFilter = .linear
        noiseBackgroundLayer.compositingFilter = "softLightBlendMode"
        noiseBackgroundLayer.isHidden = true

        layer?.addSublayer(solidBackgroundLayer)
        layer?.addSublayer(gradientBackgroundLayer)
        layer?.addSublayer(dynamicBackgroundLayer)
        layer?.addSublayer(noiseBackgroundLayer)
        layer?.addSublayer(selectionLayer)
    }

    required init?(coder: NSCoder) { fatalError("unused") }

    /// AppKit default is y-up. We use y-down (CSS/extension convention) for documentPt.
    override var isFlipped: Bool { true }

    private func updateFrameAndLayers(previous: EditorDocument?) {
        guard let doc = document else {
            frame = .zero
            solidBackgroundLayer.isHidden = true
            gradientBackgroundLayer.isHidden = true
            dynamicBackgroundLayer.isHidden = true
            noiseBackgroundLayer.isHidden = true
            dynamicBackgroundLayer.contents = nil
            selectionContentLayer.contents = nil
            selectionContentLayer.mask = nil
            pendingBGOperation?.cancel()
            pendingBGOperation = nil
            return
        }
        frame = doc.imageBounds

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        defer { CATransaction.commit() }

        let selectionMovedForDynamic = doc.background.kind == .dynamic
            && previous?.baseSelection != doc.baseSelection
        let backgroundChanged = previous == nil
            || previous?.screenshot !== doc.screenshot
            || previous?.padding != doc.padding
            || previous?.background != doc.background
            || previous?.backgroundEffects != doc.backgroundEffects
            || previous?.screenshotCornerOverride != doc.screenshotCornerOverride
            || selectionMovedForDynamic
        if backgroundChanged {
            updateBackground(for: doc)
        }

        let selectionChanged = previous == nil
            || previous?.screenshot !== doc.screenshot
            || previous?.baseSelection != doc.baseSelection
            || previous?.selectionCornerRadii != doc.selectionCornerRadii
            || previous?.padding != doc.padding
            || previous?.screenshotCornerOverride != doc.screenshotCornerOverride
            || previous?.shadow != doc.shadow
        if selectionChanged {
            updateSelection(for: doc)
        }
    }

    private func updateBackground(for doc: EditorDocument) {
        let backgroundFrame = doc.effectiveCrop.integral
        solidBackgroundLayer.frame = backgroundFrame
        gradientBackgroundLayer.frame = backgroundFrame
        dynamicBackgroundLayer.frame = backgroundFrame
        noiseBackgroundLayer.frame = backgroundFrame

        solidBackgroundLayer.isHidden = true
        gradientBackgroundLayer.isHidden = true
        dynamicBackgroundLayer.isHidden = true
        noiseBackgroundLayer.isHidden = true

        for layer in [solidBackgroundLayer, gradientBackgroundLayer, dynamicBackgroundLayer, noiseBackgroundLayer] {
            layer.filters = nil
            layer.mask = nil
            layer.cornerRadius = 0
            layer.masksToBounds = false
        }

        guard !doc.padding.isZero, doc.background.kind != .none else {
            pendingDynamicSource = nil
            pendingDynamicSelection = .null
            pendingBGToken = nil
            pendingBGOperation?.cancel()
            pendingBGOperation = nil
            dynamicBackgroundLayer.contents = nil
            blurContentLayer.contents = nil
            noiseBackgroundLayer.opacity = 0
            hideBlurContent()
            publishBackgroundLanded(for: doc)
            return
        }

        updateNoiseOverlay(for: doc, size: backgroundFrame.size)

        // Live GPU blur: render the unblurred base once into the overscan child,
        // then a gaussian on that child blurs it so radius drags only swap filters.
        if doc.backgroundEffects.clamped.blurRadius > 0 {
            pendingDynamicSource = nil
            pendingDynamicSelection = .null
            dynamicBackgroundLayer.isHidden = false
            applyOuterMask(to: dynamicBackgroundLayer, doc: doc, size: backgroundFrame.size)
            dynamicBackgroundLayer.masksToBounds = true
            let margin = Self.liveBlurMargin
            let radius = doc.backgroundEffects.clamped.blurRadius
            blurContentLayer.isHidden = false
            blurContentLayer.frame = CGRect(x: -margin, y: -margin,
                                            width: backgroundFrame.width + margin * 2,
                                            height: backgroundFrame.height + margin * 2)
            // Rebuild only on radius change; re-setting each tick flickers.
            if liveBlurRadius != radius {
                blurContentLayer.filters = Self.liveBlurFilters(radius: radius)
                liveBlurRadius = radius
            }
            updateBlurSource(for: doc, size: backgroundFrame.size, margin: margin)
            return
        }
        hideBlurContent()
        pendingBGToken = nil
        pendingBGOperation?.cancel()
        pendingBGOperation = nil

        switch doc.background {
        case .none:
            break
        case .solidColor(let color):
            dynamicBackgroundLayer.contents = nil
            solidBackgroundLayer.backgroundColor = color
            solidBackgroundLayer.isHidden = false
            applyOuterMask(to: solidBackgroundLayer, doc: doc, size: backgroundFrame.size)
            publishBackgroundLanded(for: doc)
        case .gradient(let start, let end, let angleDegrees):
            dynamicBackgroundLayer.contents = nil
            gradientBackgroundLayer.colors = [start, end]
            let points = Self.gradientPoints(angleDegrees: angleDegrees, size: backgroundFrame.size)
            gradientBackgroundLayer.startPoint = points.start
            gradientBackgroundLayer.endPoint = points.end
            gradientBackgroundLayer.isHidden = false
            applyOuterMask(to: gradientBackgroundLayer, doc: doc, size: backgroundFrame.size)
            publishBackgroundLanded(for: doc)
        case .dynamic:
            updateDynamicBackground(for: doc)
            dynamicBackgroundLayer.isHidden = false
            applyOuterMask(to: dynamicBackgroundLayer, doc: doc, size: backgroundFrame.size)
        case .image:
            // Aspect-fill the wallpaper via the shared composed-image path; noise
            // stays a separate overlay so we pass the noise-free document here.
            updateComposedBackground(for: doc.withoutPreviewNoise, size: backgroundFrame.size)
            dynamicBackgroundLayer.isHidden = false
            applyOuterMask(to: dynamicBackgroundLayer, doc: doc, size: backgroundFrame.size)
        }
    }

    private func updateNoiseOverlay(for doc: EditorDocument, size: CGSize) {
        let opacity = Self.previewNoiseOpacity(for: doc.backgroundEffects.clamped.noiseOpacity)
        guard opacity > 0 else {
            noiseBackgroundLayer.opacity = 0
            noiseBackgroundLayer.isHidden = true
            return
        }
        noiseBackgroundLayer.opacity = opacity
        noiseBackgroundLayer.isHidden = false
        applyOuterMask(to: noiseBackgroundLayer, doc: doc, size: size)
    }

    private func updateDynamicBackground(for doc: EditorDocument) {
        let screenshot = doc.screenshot
        let selection = doc.baseSelection
        if let cached = DynamicMeshCache.shared.cachedMeshImage(for: screenshot, selection: selection) {
            dynamicBackgroundLayer.contents = cached
            pendingDynamicSource = nil
            pendingDynamicSelection = .null
            publishBackgroundLanded(for: doc)
            return
        }

        // Keep the previous mesh visible until the new one is ready (no flicker /
        // vanishing band during inset drags that swap the screenshot each frame).
        guard pendingDynamicSource !== screenshot || pendingDynamicSelection != selection else { return }
        pendingDynamicSource = screenshot
        pendingDynamicSelection = selection

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let image = DocumentRenderer.dynamicBackgroundImage(for: screenshot, selection: selection)
            DispatchQueue.main.async {
                guard let self else { return }
                if self.pendingDynamicSource === screenshot && self.pendingDynamicSelection == selection {
                    self.pendingDynamicSource = nil
                    self.pendingDynamicSelection = .null
                }
                guard let current = self.document,
                      current.background.kind == .dynamic,
                      !current.backgroundEffects.isActive,
                      current.screenshot === screenshot,
                      current.baseSelection == selection else { return }
                self.setContentsWithoutAnimation(self.dynamicBackgroundLayer, image)
                self.publishBackgroundLanded(for: current)
            }
        }
    }

    private func hideBlurContent() {
        guard liveBlurRadius >= 0 else { return }
        blurContentLayer.isHidden = true
        blurContentLayer.contents = nil
        blurContentLayer.filters = nil
        liveBlurRadius = -1
    }

    /// Swaps layer contents without the default cross-fade. Async callbacks land
    /// outside the layout CATransaction, so the implicit fade would flash on swap.
    private func setContentsWithoutAnimation(_ layer: CALayer, _ image: CGImage?) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer.contents = image
        CATransaction.commit()
    }

    /// Gaussian for the overscan child, which supplies the edge pixels it needs.
    static func liveBlurFilters(radius: CGFloat) -> [CIFilter] {
        guard radius > 0, let blur = CIFilter(name: "CIGaussianBlur") else { return [] }
        blur.setValue(radius, forKey: kCIInputRadiusKey)
        return [blur]
    }

    /// Renders the unblurred base into the overscan child. Keyed on style/size so
    /// radius-only drags reuse the in-flight render and blur stays a filter swap.
    private func updateBlurSource(for doc: EditorDocument, size: CGSize, margin: CGFloat) {
        let enlarged = CGSize(width: size.width + margin * 2, height: size.height + margin * 2)
        let token = BackgroundToken(
            screenshot: ObjectIdentifier(doc.screenshot),
            selection: doc.baseSelection,
            style: doc.background,
            effects: .none,
            size: enlarged
        )
        guard pendingBGToken != token else { return }
        pendingBGToken = token

        pendingBGOperation?.cancel()
        let operation = BlockOperation()
        operation.addExecutionBlock { [weak operation, weak self] in
            guard operation?.isCancelled == false else { return }
            let image = DocumentRenderer.overscanBaseBackgroundImage(for: doc, margin: margin)
            guard operation?.isCancelled == false else { return }
            DispatchQueue.main.async {
                guard let self,
                      operation?.isCancelled == false,
                      self.pendingBGToken == token,
                      let image else { return }
                self.setContentsWithoutAnimation(self.blurContentLayer, image)
                self.publishBackgroundLanded(for: doc)
                if self.pendingBGOperation === operation {
                    self.pendingBGOperation = nil
                }
            }
        }
        pendingBGOperation = operation
        composedBackgroundQueue.addOperation(operation)
    }

    /// Renders the composed (fill + blur + noise) background off the main thread and
    /// installs it as the image layer's contents. Keeps the previous image visible
    /// until the new one is ready (no flicker during slider drags).
    private func updateComposedBackground(for doc: EditorDocument, size: CGSize) {
        let token = BackgroundToken(
            screenshot: ObjectIdentifier(doc.screenshot),
            selection: doc.baseSelection,
            style: doc.background,
            effects: doc.backgroundEffects,
            size: size
        )
        guard pendingBGToken != token else { return }
        pendingBGToken = token

        pendingBGOperation?.cancel()
        let operation = BlockOperation()
        operation.addExecutionBlock { [weak operation, weak self] in
            guard operation?.isCancelled == false else { return }
            let image = DocumentRenderer.composedBackgroundImage(for: doc)
            guard operation?.isCancelled == false else { return }
            DispatchQueue.main.async {
                guard let self,
                      operation?.isCancelled == false,
                      self.pendingBGToken == token,
                      let image else { return }
                self.setContentsWithoutAnimation(self.dynamicBackgroundLayer, image)
                self.publishBackgroundLanded(for: doc)
                if self.pendingBGOperation === operation {
                    self.pendingBGOperation = nil
                }
            }
        }
        pendingBGOperation = operation
        composedBackgroundQueue.addOperation(operation)
    }

    private func applyOuterMask(to layer: CALayer, doc: EditorDocument, size: CGSize) {
        if let radius = doc.cardCornerRadius {
            layer.cornerCurve = .continuous
            layer.cornerRadius = radius
            layer.maskedCorners = [
                .layerMinXMinYCorner, .layerMaxXMinYCorner,
                .layerMinXMaxYCorner, .layerMaxXMaxYCorner
            ]
            layer.masksToBounds = true
            layer.mask = nil
        }
    }

    private func publishBackgroundLanded(for doc: EditorDocument) {
        onBackgroundLanded?(CanvasBackgroundLanding(
            background: doc.background,
            effectiveCrop: doc.effectiveCrop
        ))
    }

    private static func previewNoiseOpacity(for strength: CGFloat) -> Float {
        let reference: CGFloat = 0.20
        let maxAmount = BackgroundEffects.maximumNoiseOpacity / reference
        let amount = min(max(strength / reference, 0), maxAmount)
        return Float(0.05 + amount * 0.18)
    }

    private static let noiseTexture: CGImage? = {
        let width = 1024
        let height = 1024
        var state: UInt64 = 0x9E37_79B9_7F4A_7C15
        var pixels = [UInt8](repeating: 0, count: width * height * 4)

        func nextByte() -> UInt8 {
            state &+= 0x9E37_79B9_7F4A_7C15
            var value = state
            value = (value ^ (value >> 30)) &* 0xBF58_476D_1CE4_E5B9
            value = (value ^ (value >> 27)) &* 0x94D0_49BB_1331_11EB
            return UInt8(truncatingIfNeeded: (value ^ (value >> 31)) >> 56)
        }

        for i in stride(from: 0, to: pixels.count, by: 4) {
            let value = nextByte()
            pixels[i] = value
            pixels[i + 1] = value
            pixels[i + 2] = value
            pixels[i + 3] = 255
        }

        let data = Data(pixels)
        let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
        guard let provider = CGDataProvider(data: data as CFData) else { return nil }
        return CGImage(
            width: width,
            height: height,
            bitsPerComponent: 8,
            bitsPerPixel: 32,
            bytesPerRow: width * 4,
            space: colorSpace,
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue)
                .union(CGBitmapInfo.byteOrder32Big),
            provider: provider,
            decode: nil,
            shouldInterpolate: true,
            intent: .defaultIntent
        )
    }()

    private func updateSelection(for doc: EditorDocument) {
        let selection = doc.baseSelection.integral.intersection(doc.imageBounds)
        guard !selection.isNull, !selection.isEmpty else {
            selectionLayer.frame = .zero
            selectionContentLayer.contents = nil
            selectionContentLayer.mask = nil
            selectionLayer.shadowOpacity = 0
            return
        }

        selectionLayer.frame = selection
        selectionContentLayer.frame = CGRect(origin: .zero, size: selection.size)
        selectionContentLayer.contents = doc.screenshot.cropping(to: selection)
        let radii = doc.effectiveSelectionCornerRadii.clamped(to: selection.size)
        if let r = radii.uniformRadius {
            // Apple continuous-corner (squircle), matching the system window mask.
            selectionContentLayer.cornerCurve = .continuous
            selectionContentLayer.cornerRadius = r
            selectionContentLayer.masksToBounds = true
            selectionContentLayer.mask = nil
        } else if radii.isZero {
            selectionContentLayer.cornerRadius = 0
            selectionContentLayer.masksToBounds = false
            selectionContentLayer.mask = nil
        } else {
            selectionContentLayer.cornerRadius = 0
            selectionContentLayer.masksToBounds = false
            selectionMaskLayer.frame = CGRect(origin: .zero, size: selection.size)
            selectionMaskLayer.path = radii.path(in: selectionMaskLayer.bounds)
            selectionContentLayer.mask = selectionMaskLayer
        }

        let shadow = doc.shadow
        if !doc.padding.isZero, shadow.isEnabled, shadow.opacity > 0 {
            // View is y-down (isFlipped), so a positive offsetY reads visually downward.
            selectionLayer.shadowColor = shadow.color
            selectionLayer.shadowOpacity = Float(shadow.opacity)
            selectionLayer.shadowRadius = shadow.blur
            selectionLayer.shadowOffset = CGSize(width: shadow.offsetX, height: shadow.offsetY)
            let bounds = CGRect(origin: .zero, size: selection.size)
            selectionLayer.shadowPath = radii.isZero
                ? CGPath(rect: bounds, transform: nil)
                : radii.path(in: bounds)
        } else {
            selectionLayer.shadowOpacity = 0
            selectionLayer.shadowPath = nil
        }
    }

    private static func gradientPoints(
        angleDegrees: CGFloat,
        size: CGSize
    ) -> (start: CGPoint, end: CGPoint) {
        guard size.width > 0, size.height > 0 else {
            return (CGPoint(x: 0, y: 0.5), CGPoint(x: 1, y: 0.5))
        }

        let radians = angleDegrees * .pi / 180
        let half = max(size.width, size.height) / 2
        let x = cos(radians) * half
        let y = sin(radians) * half
        return (
            CGPoint(x: 0.5 - x / size.width, y: 0.5 - y / size.height),
            CGPoint(x: 0.5 + x / size.width, y: 0.5 + y / size.height)
        )
    }
}

private extension EditorDocument {
    var withoutPreviewNoise: EditorDocument {
        var copy = self
        copy.backgroundEffects.noiseOpacity = 0
        return copy
    }
}
