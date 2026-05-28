import AppKit

/// Owns the AppKit view tree for the canvas and applies the one-shot initial
/// zoom-to-selection. Updates are pushed in from `CanvasView.updateNSView` (MainActor),
/// so no Combine subscription is needed.
@MainActor
final class CanvasCoordinator {
    let scrollView: CanvasScrollView
    let contentView: CanvasContentView
    let overlayView: CanvasOverlayView
    private let container: NSView
    private var didApplyInitialZoom = false

    init() {
        scrollView = CanvasScrollView()
        container = NSView(frame: .zero)
        container.wantsLayer = true
        container.layer?.backgroundColor = .clear
        contentView = CanvasContentView(frame: .zero)
        overlayView = CanvasOverlayView(frame: .zero)
        container.addSubview(contentView)
        container.addSubview(overlayView)
        scrollView.documentView = container
    }

    /// Push the latest document into the view tree. Called on every SwiftUI update.
    func update(document: EditorDocument) {
        container.frame = CGRect(origin: .zero, size: document.paddedDocumentSize)
        contentView.document = document          // didSet sizes contentView's frame
        overlayView.resizeToDocument(document)   // sizes overlay frame + halo

        if !didApplyInitialZoom {
            didApplyInitialZoom = true
            let docSize = document.paddedDocumentSize
            // Run the fit when the scroll view actually has a laid-out size, not on a
            // deferred timer — fitting against a placeholder size over-zooms and clips.
            scrollView.requestInitialFit { [weak scrollView] in
                scrollView?.magnify(toFit: Self.fitRect(for: docSize))
            }
        }
    }

    /// Spec: open with the document (the crop) filling ~80% of the visible canvas.
    /// The documentView content lives in DOCUMENT space: origin (0,0), size docSize.
    /// effectiveCrop's origin is in IMAGE-pixel space and must NOT be used here, or the
    /// fit would frame an empty region for any selection not at the image origin.
    private static func fitRect(for docSize: CGSize) -> CGRect {
        let inset: CGFloat = 0.10  // 10% margin each side ≈ 80% fill
        return CGRect(
            x: -docSize.width * inset,
            y: -docSize.height * inset,
            width: docSize.width * (1 + inset * 2),
            height: docSize.height * (1 + inset * 2)
        )
    }
}
