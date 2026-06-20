import AppKit

/// Hosts the selected region of the screenshot at 1:1 pixel size. The surrounding
/// page is not drawn — only the selection layer is visible. The
/// full screenshot stays in `EditorDocument.screenshot` for tools that need it.
final class CanvasContentView: NSView {

    var document: EditorDocument? {
        didSet { updateFrameAndLayers(previous: oldValue) }
    }

    private let solidBackgroundLayer: CALayer
    private let gradientBackgroundLayer: CAGradientLayer
    private let dynamicBackgroundLayer: CALayer
    private let noiseBackgroundLayer: CALayer
    private let selectionLayer: CALayer
    private let selectionMaskLayer: CAShapeLayer
    private let composedBackgroundQueue: OperationQueue
    private var pendingDynamicSource: CGImage?
    private var pendingDynamicSelection: CGRect = .null
    private var pendingBGToken: BackgroundToken?
    private var pendingBGOperation: Operation?

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
        self.noiseBackgroundLayer = CALayer()
        self.selectionLayer = CALayer()
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
        selectionLayer.contentsGravity = .resize
        selectionLayer.magnificationFilter = .trilinear
        selectionLayer.minificationFilter = .trilinear
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
            selectionLayer.contents = nil
            selectionLayer.mask = nil
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
            || previous?.cardCornerOverride != doc.cardCornerOverride
            || previous?.backgroundEffects != doc.backgroundEffects
            || previous?.screenshotCornerOverride != doc.screenshotCornerOverride
            || previous?.lockCornersToCard != doc.lockCornersToCard
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
            || previous?.lockCornersToCard != doc.lockCornersToCard
            || previous?.cardCornerOverride != doc.cardCornerOverride
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
            noiseBackgroundLayer.opacity = 0
            return
        }

        updateNoiseOverlay(for: doc, size: backgroundFrame.size)

        // Blur needs a composed base image. Noise stays as a lightweight overlay
        // so slider drags only adjust layer opacity instead of re-rendering.
        if doc.backgroundEffects.clamped.blurRadius > 0 {
            pendingDynamicSource = nil
            pendingDynamicSelection = .null
            dynamicBackgroundLayer.isHidden = false
            applyOuterMask(to: dynamicBackgroundLayer, doc: doc, size: backgroundFrame.size)
            updateComposedBackground(for: doc.withoutPreviewNoise, size: backgroundFrame.size)
            return
        }
        pendingBGToken = nil
        pendingBGOperation?.cancel()
        pendingBGOperation = nil

        switch doc.background {
        case .none:
            break
        case .solidColor(let color):
            solidBackgroundLayer.backgroundColor = color
            solidBackgroundLayer.isHidden = false
            applyOuterMask(to: solidBackgroundLayer, doc: doc, size: backgroundFrame.size)
        case .gradient(let start, let end, let angleDegrees):
            gradientBackgroundLayer.colors = [start, end]
            let points = Self.gradientPoints(angleDegrees: angleDegrees, size: backgroundFrame.size)
            gradientBackgroundLayer.startPoint = points.start
            gradientBackgroundLayer.endPoint = points.end
            gradientBackgroundLayer.isHidden = false
            applyOuterMask(to: gradientBackgroundLayer, doc: doc, size: backgroundFrame.size)
        case .dynamic:
            updateDynamicBackground(for: doc)
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
                self.dynamicBackgroundLayer.contents = image
            }
        }
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
                self.dynamicBackgroundLayer.contents = image
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
        } else if !doc.outerCornerRadii.isZero {
            let maskLayer = CAShapeLayer()
            maskLayer.frame = CGRect(origin: .zero, size: size)
            maskLayer.path = doc.outerCornerRadii.path(in: maskLayer.bounds)
            layer.mask = maskLayer
        }
    }

    private static func previewNoiseOpacity(for strength: CGFloat) -> Float {
        let reference: CGFloat = 0.20
        let maxAmount = BackgroundEffects.maximumNoiseOpacity / reference
        let amount = min(max(strength / reference, 0), maxAmount)
        return Float(0.05 + amount * 0.085)
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
            selectionLayer.contents = nil
            selectionLayer.mask = nil
            selectionLayer.shadowOpacity = 0
            return
        }

        selectionLayer.frame = selection
        selectionLayer.contents = doc.screenshot.cropping(to: selection)
        let radii = doc.effectiveSelectionCornerRadii.clamped(to: selection.size)
        if radii.isZero {
            selectionLayer.mask = nil
        } else {
            selectionMaskLayer.frame = CGRect(origin: .zero, size: selection.size)
            selectionMaskLayer.path = radii.path(in: selectionMaskLayer.bounds)
            selectionLayer.mask = selectionMaskLayer
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
