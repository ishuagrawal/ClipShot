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
        let imageBounds = document.imageBounds
        container.frame = imageBounds
        contentView.document = document          // didSet sizes contentView's frame
        overlayView.resizeToDocument(document)   // sizes overlay frame

        if !didApplyInitialZoom {
            didApplyInitialZoom = true
            let selection = document.baseSelection.integral.intersection(imageBounds)
            // Run the fit when the scroll view actually has a laid-out size, not on a
            // deferred timer — fitting against a placeholder size over-zooms and clips.
            scrollView.requestInitialFit { [weak scrollView] in
                guard let scrollView else { return }
                let fitRect = Self.initialFitRect(
                    for: selection,
                    in: scrollView.contentView.bounds.size
                )
                scrollView.magnify(toFit: fitRect.isNull || fitRect.isEmpty ? imageBounds : fitRect)
            }
        }
    }

    /// Spec: open centered on the selected region, with the selection occupying
    /// about 80% of the visible canvas and the rest showing faded page context.
    /// Returns a document-space rect with the same aspect ratio as the viewport.
    nonisolated static func initialFitRect(for selection: CGRect, in viewportSize: CGSize) -> CGRect {
        guard !selection.isNull,
              !selection.isEmpty,
              viewportSize.width > 0,
              viewportSize.height > 0 else {
            return selection
        }

        let selectedFill: CGFloat = 0.80
        let viewportAspect = viewportSize.width / viewportSize.height
        let minWidth = selection.width / selectedFill
        let minHeight = selection.height / selectedFill

        var fitSize = CGSize(width: minWidth, height: minWidth / viewportAspect)
        if fitSize.height < minHeight {
            fitSize.height = minHeight
            fitSize.width = minHeight * viewportAspect
        }

        return CGRect(
            x: selection.midX - fitSize.width / 2,
            y: selection.midY - fitSize.height / 2,
            width: fitSize.width,
            height: fitSize.height
        )
    }
}
