import AppKit

/// Hosts the full screenshot at 1:1 pixel size. The page context is faded, while
/// the selected region is drawn again at full opacity in the same document space.
final class CanvasContentView: NSView {

    var document: EditorDocument? {
        didSet { updateFrameAndLayer() }
    }

    private let contextLayer: CALayer
    private let selectionLayer: CALayer

    override init(frame frameRect: NSRect) {
        self.contextLayer = CALayer()
        self.selectionLayer = CALayer()
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor(white: 0.06, alpha: 1).cgColor

        contextLayer.contentsGravity = .resize
        contextLayer.magnificationFilter = .trilinear
        contextLayer.minificationFilter = .trilinear
        contextLayer.opacity = 0.06

        selectionLayer.contentsGravity = .resize
        selectionLayer.magnificationFilter = .trilinear
        selectionLayer.minificationFilter = .trilinear

        layer?.addSublayer(contextLayer)
        layer?.addSublayer(selectionLayer)
    }

    required init?(coder: NSCoder) { fatalError("unused") }

    /// AppKit default is y-up. We use y-down (CSS/extension convention) for documentPt.
    override var isFlipped: Bool { true }

    private func updateFrameAndLayer() {
        guard let doc = document else {
            frame = .zero
            contextLayer.contents = nil
            selectionLayer.contents = nil
            return
        }
        frame = doc.imageBounds

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        contextLayer.frame = bounds
        contextLayer.contents = doc.screenshot

        let selection = doc.baseSelection.integral.intersection(doc.imageBounds)
        if selection.isNull || selection.isEmpty {
            selectionLayer.frame = .zero
            selectionLayer.contents = nil
        } else {
            selectionLayer.frame = selection
            selectionLayer.contents = doc.screenshot.cropping(to: selection)
        }
        CATransaction.commit()
    }
}
