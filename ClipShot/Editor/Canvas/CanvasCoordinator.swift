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
            applyInitialZoomToSelection(document: document)
        }
    }

    /// Spec: open with the effective crop filling ~80% of the visible canvas.
    /// Deferred one runloop tick so the scroll view has a valid size to fit against.
    private func applyInitialZoomToSelection(document: EditorDocument) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            let crop = document.effectiveCrop
            let inset: CGFloat = 0.10  // 10% margin each side ≈ 80% fill
            let targetRect = CGRect(
                x: crop.minX - crop.width * inset,
                y: crop.minY - crop.height * inset,
                width: crop.width * (1 + inset * 2),
                height: crop.height * (1 + inset * 2)
            )
            self.scrollView.magnify(toFit: targetRect)
        }
    }
}
