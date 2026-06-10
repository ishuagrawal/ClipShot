import AppKit

/// Owns the AppKit view tree for the canvas and applies the one-shot initial
/// zoom-to-selection. Updates are pushed in from `CanvasView.updateNSView` (MainActor),
/// so no Combine subscription is needed.
@MainActor
final class CanvasCoordinator {
    private nonisolated static let preferredInitialViewportMargin: CGFloat = 96
    private nonisolated static let minimumInitialViewportMargin: CGFloat = 32

    let scrollView: CanvasScrollView
    let contentView: CanvasContentView
    let overlayView: CanvasOverlayView
    let interactionView: CanvasInteractionView
    let textEditor: CanvasTextEditor
    private let container: CanvasDocumentView
    private var didApplyInitialZoom = false
    private var initialPlacement: CanvasInitialPlacement?
    private var latestDocument: EditorDocument?
    private var isTrackingInitialSelectionFit = false

    /// Forwarded to the zoom controller so the SwiftUI readout tracks the live zoom.
    var onMagnificationChange: ((CGFloat) -> Void)?
    var currentMagnification: CGFloat { scrollView.magnification }

    init() {
        scrollView = CanvasScrollView()
        container = CanvasDocumentView(frame: .zero)
        container.wantsLayer = true
        container.layer?.backgroundColor = .clear
        contentView = CanvasContentView(frame: .zero)
        overlayView = CanvasOverlayView(frame: .zero)
        interactionView = CanvasInteractionView(frame: .zero)
        interactionView.wantsLayer = true
        // None of these views draw in draw(_:) — everything is CALayer content.
        // Tell AppKit so it never re-renders them during scrolling or zooming.
        for view in [container, contentView, overlayView, interactionView] {
            view.layerContentsRedrawPolicy = .onSetNeedsDisplay
        }
        textEditor = CanvasTextEditor(container: container)
        textEditor.onEditingPreviewChanged = { [weak self] annotation in
            self?.overlayView.editingTextAnnotation = annotation
            self?.interactionView.editingTextAnnotation = annotation
        }
        container.addSubview(contentView)
        container.addSubview(overlayView)
        container.addSubview(interactionView)
        interactionView.scrollView = scrollView
        interactionView.onEditText = { [weak self] annotation in
            guard let self else { return }
            self.textEditor.beginEditing(
                annotation,
                baseSelection: self.latestDocument?.baseSelection ?? .zero
            )
        }
        interactionView.onCommitActiveText = { [weak self] in
            guard let self, self.textEditor.isEditing else { return false }
            self.textEditor.finishEditing()
            return true
        }
        interactionView.onHoverAnnotationChanged = { [weak self] id in
            self?.overlayView.hoveredAnnotationID = id
        }
        scrollView.documentView = container
        // The floating inspector column covers this much of the right edge;
        // fits center the document in the clear space left of it.
        scrollView.rightOcclusionInset = Theme.rightChromeWidth
        scrollView.viewportSizeDidChange = { [weak self] viewportSize in
            self?.refitInitialSelectionIfNeeded(viewportSize: viewportSize)
        }
        scrollView.userInteractionDidStart = { [weak self] in
            self?.isTrackingInitialSelectionFit = false
        }
        scrollView.magnificationDidChange = { [weak self] mag in
            self?.onMagnificationChange?(mag)
        }
    }

    // MARK: - Zoom control actions

    /// Set an explicit zoom level (from the +/- buttons or percentage dropdown).
    func controlZoom(to value: CGFloat) {
        isTrackingInitialSelectionFit = false
        scrollView.setMagnificationFromControl(value)
    }

    /// Fill the viewport with the selected screenshot region (edge-to-edge, no margin).
    func fitSelectionToCanvas() {
        guard let document = latestDocument else { return }
        isTrackingInitialSelectionFit = false
        let imageBounds = document.imageBounds
        let selection = document.baseSelection.integral.intersection(imageBounds)
        let target = (selection.isNull || selection.isEmpty) ? imageBounds : selection
        let placement = initialPlacement ?? CanvasInitialPlacement.default(imageBounds: imageBounds)
        // `selection` is image-space (origin = image top-left); offset into container space.
        let rectInContainer = target.offsetBy(dx: placement.imageFrame.minX, dy: placement.imageFrame.minY)
        scrollView.magnify(toFitCenteredOn: rectInContainer)
    }

    /// Restore the initial load framing (padded card centered with a comfortable margin).
    func resetToInitialFit() {
        isTrackingInitialSelectionFit = true
        refitInitialSelectionIfNeeded(viewportSize: scrollView.viewportSizeForFitting, force: true)
    }

    /// Push the latest document into the view tree. Called on every SwiftUI update.
    func update(state: EditorState) {
        let document = state.document
        latestDocument = document
        let imageBounds = document.imageBounds
        let placement = initialPlacement ?? CanvasInitialPlacement.default(imageBounds: imageBounds)
        apply(document: document, placement: placement)
        overlayView.inProgressAnnotation = state.inProgressAnnotation
        overlayView.selectedAnnotationID = state.selectedAnnotationID
        interactionView.state = state
        interactionView.baseSelection = document.baseSelection
        textEditor.attach(state: state)
        if textEditor.isEditing, state.activeTool != .text {
            textEditor.finishEditing()
        }
        textEditor.imageFrameOrigin = contentView.frame.origin
        textEditor.syncEditingField(with: document, baseSelection: document.baseSelection)

        if !didApplyInitialZoom {
            didApplyInitialZoom = true
            isTrackingInitialSelectionFit = true
            // Run the fit when the scroll view actually has a laid-out size, not on a
            // deferred timer — fitting against a placeholder size over-zooms and clips.
            scrollView.requestInitialFit { [weak self, weak scrollView] in
                guard let self, let scrollView else { return }
                self.refitInitialSelectionIfNeeded(
                    viewportSize: scrollView.viewportSizeForFitting,
                    force: true
                )
            }
        }
    }

    private func apply(document: EditorDocument, placement: CanvasInitialPlacement) {
        container.frame = placement.canvasFrame
        contentView.document = document          // didSet sizes contentView's frame
        contentView.frame = placement.imageFrame
        overlayView.resizeToDocument(document)   // sizes overlay frame
        overlayView.frame = placement.imageFrame
        let interactionBounds = document.effectiveCrop.integral
        interactionView.imageSpaceOrigin = interactionBounds.origin
        interactionView.frame = interactionBounds.offsetBy(
            dx: placement.imageFrame.minX,
            dy: placement.imageFrame.minY
        )
    }

    private func refitInitialSelectionIfNeeded(viewportSize: CGSize, force: Bool = false) {
        guard (force || isTrackingInitialSelectionFit),
              let document = latestDocument else {
            return
        }

        let imageBounds = document.imageBounds
        let focusBounds = Self.initialFocusBounds(
            effectiveCrop: document.effectiveCrop,
            imageBounds: imageBounds
        )
        guard viewportSize.width > 0, viewportSize.height > 0 else { return }

        // Build the fit against the unobstructed region so its aspect matches
        // what magnify(toFitCenteredOn:) will fit into.
        var effectiveViewport = viewportSize
        effectiveViewport.width = max(1, effectiveViewport.width - scrollView.rightOcclusionInset)
        let fitRect = Self.initialFitRect(
            for: focusBounds,
            in: effectiveViewport
        )
        let targetRect = fitRect.isNull || fitRect.isEmpty ? imageBounds : fitRect
        let placement = CanvasInitialPlacement(
            imageBounds: imageBounds,
            targetRect: targetRect
        )
        initialPlacement = placement
        apply(document: document, placement: placement)
        scrollView.magnify(toFitCenteredOn: placement.targetRect)
    }

    /// Spec: open centered on the padded card, with a comfortable viewport
    /// margin around the rendered output. The surrounding page context may extend
    /// beyond the visible canvas.
    /// Returns a document-space rect with the same aspect ratio as the viewport.
    nonisolated static func initialFitRect(for selection: CGRect, in viewportSize: CGSize) -> CGRect {
        guard !selection.isNull,
              !selection.isEmpty,
              viewportSize.width > 0,
              viewportSize.height > 0 else {
            return selection
        }

        let margin = initialViewportMargin(for: viewportSize)
        let innerWidth = max(1, viewportSize.width - margin * 2)
        let innerHeight = max(1, viewportSize.height - margin * 2)
        let viewportAspect = viewportSize.width / viewportSize.height
        let selectedScale = min(innerWidth / selection.width, innerHeight / selection.height)
        let targetWidth = viewportSize.width / selectedScale
        let targetHeight = viewportSize.height / selectedScale

        var fitSize = CGSize(width: targetWidth, height: targetWidth / viewportAspect)
        if fitSize.height < targetHeight {
            fitSize.height = targetHeight
            fitSize.width = targetHeight * viewportAspect
        }

        return CGRect(
            x: selection.midX - fitSize.width / 2,
            y: selection.midY - fitSize.height / 2,
            width: fitSize.width,
            height: fitSize.height
        )
    }

    nonisolated static func initialFocusBounds(effectiveCrop: CGRect, imageBounds: CGRect) -> CGRect {
        let cardBounds = effectiveCrop.integral
        return cardBounds.isNull || cardBounds.isEmpty ? imageBounds : cardBounds
    }

    nonisolated static func initialViewportMargin(for viewportSize: CGSize) -> CGFloat {
        let shortestSide = min(viewportSize.width, viewportSize.height)
        guard shortestSide > 0 else { return 0 }

        let adaptiveMargin = min(
            preferredInitialViewportMargin,
            max(minimumInitialViewportMargin, shortestSide * 0.16)
        )
        let maximumUsableMargin = max(0, (shortestSide - 1) / 2)
        return min(adaptiveMargin, maximumUsableMargin)
    }
}

final class CanvasDocumentView: NSView {
    /// Match the DOM/screenshot coordinate system used by CanvasContentView:
    /// origin at the top-left, y increasing downward.
    override var isFlipped: Bool { true }
}

struct CanvasInitialPlacement: Equatable {
    let canvasFrame: CGRect
    let imageFrame: CGRect
    let targetRect: CGRect

    static func `default`(imageBounds: CGRect) -> CanvasInitialPlacement {
        CanvasInitialPlacement(
            canvasFrame: CGRect(origin: .zero, size: imageBounds.size),
            imageFrame: CGRect(origin: .zero, size: imageBounds.size),
            targetRect: imageBounds
        )
    }

    init(canvasFrame: CGRect, imageFrame: CGRect, targetRect: CGRect) {
        self.canvasFrame = canvasFrame
        self.imageFrame = imageFrame
        self.targetRect = targetRect
    }

    init(imageBounds: CGRect, targetRect: CGRect) {
        // Free-roam margin: the canvas extends well past the document on every
        // side, so the image can be panned anywhere in the viewport instead of
        // stopping at its own edges.
        let union = imageBounds.union(targetRect)
        let margin = max(union.width, union.height)
        let canvasBounds = union.insetBy(dx: -margin, dy: -margin)
        let offset = CGPoint(x: -canvasBounds.minX, y: -canvasBounds.minY)
        canvasFrame = CGRect(origin: .zero, size: canvasBounds.size)
        imageFrame = imageBounds.offsetBy(dx: offset.x, dy: offset.y)
        self.targetRect = targetRect.offsetBy(dx: offset.x, dy: offset.y)
    }
}
