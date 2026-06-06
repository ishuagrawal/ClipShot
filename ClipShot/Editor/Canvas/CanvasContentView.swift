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
    private let selectionLayer: CALayer
    private let selectionMaskLayer: CAShapeLayer
    private let backgroundMaskLayer: CAShapeLayer

    override init(frame frameRect: NSRect) {
        self.solidBackgroundLayer = CALayer()
        self.gradientBackgroundLayer = CAGradientLayer()
        self.dynamicBackgroundLayer = CALayer()
        self.selectionLayer = CALayer()
        self.selectionMaskLayer = CAShapeLayer()
        self.backgroundMaskLayer = CAShapeLayer()
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = .clear
        layer?.masksToBounds = false

        dynamicBackgroundLayer.contentsGravity = .resize
        dynamicBackgroundLayer.magnificationFilter = .trilinear
        dynamicBackgroundLayer.minificationFilter = .trilinear
        selectionLayer.contentsGravity = .resize
        selectionLayer.magnificationFilter = .trilinear
        selectionLayer.minificationFilter = .trilinear

        layer?.addSublayer(solidBackgroundLayer)
        layer?.addSublayer(gradientBackgroundLayer)
        layer?.addSublayer(dynamicBackgroundLayer)
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
            dynamicBackgroundLayer.contents = nil
            selectionLayer.contents = nil
            selectionLayer.mask = nil
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
            || selectionMovedForDynamic
        if backgroundChanged {
            updateBackground(for: doc)
        }

        let selectionChanged = previous == nil
            || previous?.screenshot !== doc.screenshot
            || previous?.baseSelection != doc.baseSelection
            || previous?.selectionCornerRadii != doc.selectionCornerRadii
        if selectionChanged {
            updateSelection(for: doc)
        }
    }

    private func updateBackground(for doc: EditorDocument) {
        let backgroundFrame = doc.effectiveCrop.integral
        solidBackgroundLayer.frame = backgroundFrame
        gradientBackgroundLayer.frame = backgroundFrame
        dynamicBackgroundLayer.frame = backgroundFrame

        solidBackgroundLayer.isHidden = true
        gradientBackgroundLayer.isHidden = true
        dynamicBackgroundLayer.isHidden = true

        for layer in [solidBackgroundLayer, gradientBackgroundLayer, dynamicBackgroundLayer] {
            layer.mask = nil
            layer.cornerRadius = 0
            layer.masksToBounds = false
        }

        guard !doc.padding.isZero else { return }

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
            dynamicBackgroundLayer.contents = DocumentRenderer.dynamicBackgroundImage(
                for: doc.screenshot,
                selection: doc.baseSelection,
                size: backgroundFrame.size
            )
            dynamicBackgroundLayer.isHidden = false
            applyOuterMask(to: dynamicBackgroundLayer, doc: doc, size: backgroundFrame.size)
        }
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
            backgroundMaskLayer.frame = CGRect(origin: .zero, size: size)
            backgroundMaskLayer.path = doc.outerCornerRadii.path(in: backgroundMaskLayer.bounds)
            layer.mask = backgroundMaskLayer
        }
    }

    private func updateSelection(for doc: EditorDocument) {
        let selection = doc.baseSelection.integral.intersection(doc.imageBounds)
        guard !selection.isNull, !selection.isEmpty else {
            selectionLayer.frame = .zero
            selectionLayer.contents = nil
            selectionLayer.mask = nil
            return
        }

        selectionLayer.frame = selection
        selectionLayer.contents = doc.screenshot.cropping(to: selection)
        let radii = doc.selectionCornerRadii.clamped(to: selection.size)
        if radii.isZero {
            selectionLayer.mask = nil
        } else {
            selectionMaskLayer.frame = CGRect(origin: .zero, size: selection.size)
            selectionMaskLayer.path = radii.path(in: selectionMaskLayer.bounds)
            selectionLayer.mask = selectionMaskLayer
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
