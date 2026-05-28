import AppKit

/// Sits above CanvasContentView inside the same documentView. Draws the selection
/// halo (blue glow around the base selection). In P2, also hosts one CALayer per
/// annotation.
///
/// The halo is UI chrome — NEVER part of the rendered export.
final class CanvasOverlayView: NSView {

    var document: EditorDocument? {
        didSet { updateHalo() }
    }

    private let haloLayer: CAShapeLayer

    override init(frame frameRect: NSRect) {
        haloLayer = CAShapeLayer()
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = .clear
        haloLayer.fillColor = nil
        haloLayer.strokeColor = NSColor.systemBlue.withAlphaComponent(0.9).cgColor
        haloLayer.lineWidth = 2
        haloLayer.shadowColor = NSColor.systemBlue.cgColor
        haloLayer.shadowOpacity = 0.5
        haloLayer.shadowRadius = 6
        haloLayer.shadowOffset = .zero
        layer?.addSublayer(haloLayer)
    }

    required init?(coder: NSCoder) { fatalError("unused") }

    override var isFlipped: Bool { true }

    /// Overlay covers the entire padded document, same frame as CanvasContentView.
    /// Self-contained: sets the frame first, then assigns `document` so the halo is
    /// always drawn against the correct bounds regardless of prior call order.
    func resizeToDocument(_ doc: EditorDocument) {
        frame = CGRect(origin: .zero, size: doc.paddedDocumentSize)
        document = doc   // didSet -> updateHalo() with the now-correct bounds
    }

    private func updateHalo() {
        guard let doc = document else {
            haloLayer.path = nil
            return
        }
        let halo = CGRect(
            x: doc.padding.left,
            y: doc.padding.top,
            width: doc.baseSelection.width,
            height: doc.baseSelection.height
        )
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        haloLayer.frame = bounds
        haloLayer.path = CGPath(rect: halo, transform: nil)
        CATransaction.commit()
    }

    /// Halo is non-interactive — let clicks fall through to CanvasContentView / scroll view.
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}
