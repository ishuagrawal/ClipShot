import AppKit

/// Sits above CanvasContentView inside the same documentView. Draws the export
/// composite at `effectiveCrop` so padding/background preview matches output.
final class CanvasOverlayView: NSView {

    var document: EditorDocument? {
        didSet { updatePreview() }
    }

    private let previewLayer: CALayer

    override init(frame frameRect: NSRect) {
        previewLayer = CALayer()
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = .clear

        previewLayer.contentsGravity = .resize
        previewLayer.magnificationFilter = .trilinear
        previewLayer.minificationFilter = .trilinear
        layer?.addSublayer(previewLayer)
    }

    required init?(coder: NSCoder) { fatalError("unused") }

    override var isFlipped: Bool { true }

    /// Overlay covers the full screenshot document, same frame as CanvasContentView.
    /// Self-contained: sets the frame first, then assigns `document` so future
    /// overlay chrome is always drawn against the correct bounds.
    func resizeToDocument(_ doc: EditorDocument) {
        frame = doc.imageBounds
        document = doc
    }

    private func updatePreview() {
        guard let doc = document else {
            previewLayer.contents = nil
            previewLayer.isHidden = true
            return
        }

        CATransaction.begin()
        CATransaction.setDisableActions(true)

        let hasFrame = doc.padding != .zero || doc.background != .none
        if hasFrame {
            previewLayer.frame = doc.effectiveCrop.integral
            previewLayer.contents = DocumentRenderer.render(doc)
            previewLayer.isHidden = false
        } else {
            previewLayer.contents = nil
            previewLayer.isHidden = true
        }

        CATransaction.commit()
    }

    /// Overlay chrome is non-interactive — let clicks fall through to the canvas.
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}
