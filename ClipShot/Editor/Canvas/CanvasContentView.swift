import AppKit

/// Hosts the selected region of the screenshot at 1:1 pixel size. The surrounding
/// page is not drawn — only the selection layer is visible. The
/// full screenshot stays in `EditorDocument.screenshot` for tools that need it.
final class CanvasContentView: NSView {

    var document: EditorDocument? {
        didSet { updateFrameAndLayer() }
    }

    private let selectionLayer: CALayer
    private let selectionMaskLayer: CAShapeLayer

    override init(frame frameRect: NSRect) {
        self.selectionLayer = CALayer()
        self.selectionMaskLayer = CAShapeLayer()
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = .clear

        selectionLayer.contentsGravity = .resize
        selectionLayer.magnificationFilter = .trilinear
        selectionLayer.minificationFilter = .trilinear

        layer?.addSublayer(selectionLayer)
    }

    required init?(coder: NSCoder) { fatalError("unused") }

    /// AppKit default is y-up. We use y-down (CSS/extension convention) for documentPt.
    override var isFlipped: Bool { true }

    private func updateFrameAndLayer() {
        guard let doc = document else {
            frame = .zero
            selectionLayer.contents = nil
            selectionLayer.mask = nil
            return
        }
        frame = doc.imageBounds

        CATransaction.begin()
        CATransaction.setDisableActions(true)

        let selection = doc.baseSelection.integral.intersection(doc.imageBounds)
        if selection.isNull || selection.isEmpty {
            selectionLayer.frame = .zero
            selectionLayer.contents = nil
            selectionLayer.mask = nil
        } else {
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
        CATransaction.commit()
    }
}
