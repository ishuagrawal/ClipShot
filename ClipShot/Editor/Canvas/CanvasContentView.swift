import AppKit

/// Hosts the screenshot at 1:1 pixel size. NSScrollView applies the magnification
/// transform around this view; the view itself never scales its content.
///
/// P0: draws the screenshot crop at `effectiveCrop` origin offset. No background fill
/// (P1) and no annotations (P2) are rendered here.
final class CanvasContentView: NSView {

    var document: EditorDocument? {
        didSet { updateFrameAndLayer() }
    }

    private let imageLayer: CALayer

    override init(frame frameRect: NSRect) {
        self.imageLayer = CALayer()
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor(white: 0.06, alpha: 1).cgColor
        imageLayer.contentsGravity = .resize
        imageLayer.magnificationFilter = .trilinear
        imageLayer.minificationFilter = .trilinear
        layer?.addSublayer(imageLayer)
    }

    required init?(coder: NSCoder) { fatalError("unused") }

    /// AppKit default is y-up. We use y-down (CSS/extension convention) for documentPt.
    override var isFlipped: Bool { true }

    private func updateFrameAndLayer() {
        guard let doc = document else {
            frame = .zero
            imageLayer.contents = nil
            return
        }
        let size = doc.paddedDocumentSize
        frame = CGRect(origin: .zero, size: size)

        let screenshotFrame = CGRect(
            x: doc.padding.left,
            y: doc.padding.top,
            width: doc.baseSelection.width,
            height: doc.baseSelection.height
        )
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        imageLayer.frame = screenshotFrame
        imageLayer.contents = doc.screenshot.cropping(to: doc.baseSelection.integral)
        CATransaction.commit()
    }
}
