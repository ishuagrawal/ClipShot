import AppKit

/// Sits above CanvasContentView inside the same documentView. P0 leaves this
/// layer visually empty; later phases can host annotation handles and editor
/// controls without making them part of the rendered export.
final class CanvasOverlayView: NSView {

    var document: EditorDocument? {
        didSet {}
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = .clear
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

    /// Overlay chrome is non-interactive — let clicks fall through to the canvas.
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}
