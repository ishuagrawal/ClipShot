import AppKit

/// NSScrollView subclass that provides:
/// - native pinch-to-zoom (via `allowsMagnification = true`)
/// - cmd+scroll zoom centered on the cursor
/// - hold Space to temporarily switch to a hand/pan cursor regardless of active tool
final class CanvasScrollView: NSScrollView {

    var isSpaceHeld: Bool = false {
        didSet {
            window?.invalidateCursorRects(for: self)
        }
    }

    var viewportSizeDidChange: ((CGSize) -> Void)?
    var userInteractionDidStart: (() -> Void)?

    /// Closure that fits the document into view. Held until the scroll view has a
    /// real laid-out size, then run exactly once (see `layout()`). Avoids fitting
    /// against a zero/placeholder size during the first render pass.
    private var pendingInitialFit: (() -> Void)?
    private var lastReportedViewportSize: CGSize = .zero

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        configure()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        configure()
    }

    private func configure() {
        // Centering clip view so content smaller than the viewport is centered
        // instead of pinned to a corner.
        contentView = CenteringClipView()
        allowsMagnification = true
        minMagnification = 0.05
        maxMagnification = 16
        magnification = 1
        hasHorizontalScroller = false
        hasVerticalScroller = false
        autohidesScrollers = true
        drawsBackground = true
        backgroundColor = NSColor(white: 0.04, alpha: 1)
        horizontalScrollElasticity = .none
        verticalScrollElasticity = .none
    }

    /// Register a fit to run once the scroll view has a valid size. If a size is
    /// already available the fit runs on the next layout pass immediately.
    func requestInitialFit(_ fit: @escaping () -> Void) {
        pendingInitialFit = fit
        needsLayout = true
    }

    func magnify(toFitCenteredOn rect: CGRect) {
        guard !rect.isNull, !rect.isEmpty else { return }
        let viewportSize = viewportSizeForFitting
        guard viewportSize.width > 0, viewportSize.height > 0 else { return }

        let targetMagnification = Self.fitMagnification(
            for: rect,
            in: viewportSize,
            limits: minMagnification...maxMagnification
        )
        let center = CGPoint(x: rect.midX, y: rect.midY)

        setMagnification(targetMagnification, centeredAt: center)
        layoutSubtreeIfNeeded()
        centerDocumentPoint(center)
    }

    nonisolated static func fitMagnification(
        for rect: CGRect,
        in viewportSize: CGSize,
        limits: ClosedRange<CGFloat>
    ) -> CGFloat {
        guard !rect.isNull,
              !rect.isEmpty,
              viewportSize.width > 0,
              viewportSize.height > 0 else {
            return limits.lowerBound
        }

        let fit = min(viewportSize.width / rect.width, viewportSize.height / rect.height)
        return fit.clamped(to: limits)
    }

    override func layout() {
        super.layout()
        if bounds.width > 0, bounds.height > 0, let fit = pendingInitialFit {
            pendingInitialFit = nil
            fit()
            lastReportedViewportSize = viewportSizeForFitting
            return
        }
        reportViewportSizeIfNeeded()
    }

    // MARK: - Cmd+scroll zoom

    override func scrollWheel(with event: NSEvent) {
        userInteractionDidStart?()
        guard event.modifierFlags.contains(.command) else {
            super.scrollWheel(with: event)
            return
        }
        // Trackpad precise deltas are small/continuous; a physical mouse wheel sends
        // large line-based steps, so scale those down to a fixed notch to avoid
        // runaway zoom jumps.
        let delta: CGFloat = event.hasPreciseScrollingDeltas
            ? event.scrollingDeltaY * 0.01
            : (event.scrollingDeltaY > 0 ? 0.1 : (event.scrollingDeltaY < 0 ? -0.1 : 0))
        let zoomFactor: CGFloat = 1.0 + delta
        let newMag = (magnification * zoomFactor).clamped(to: minMagnification...maxMagnification)
        let pointInDocument = documentView?.convert(event.locationInWindow, from: nil)
            ?? convert(event.locationInWindow, from: nil)
        setMagnification(newMag, centeredAt: pointInDocument)
    }

    override func magnify(with event: NSEvent) {
        userInteractionDidStart?()
        super.magnify(with: event)
    }

    override func smartMagnify(with event: NSEvent) {
        userInteractionDidStart?()
        super.smartMagnify(with: event)
    }

    private func centerDocumentPoint(_ point: CGPoint) {
        var proposedBounds = contentView.bounds
        proposedBounds.origin = CGPoint(
            x: point.x - proposedBounds.width / 2,
            y: point.y - proposedBounds.height / 2
        )
        let constrainedBounds = contentView.constrainBoundsRect(proposedBounds)
        contentView.setBoundsOrigin(constrainedBounds.origin)
        reflectScrolledClipView(contentView)
    }

    var viewportSizeForFitting: CGSize {
        let frameSize = contentView.frame.size
        if frameSize.width > 0, frameSize.height > 0 {
            return frameSize
        }
        return bounds.size
    }

    private func reportViewportSizeIfNeeded() {
        let size = viewportSizeForFitting
        guard size.width > 0, size.height > 0 else { return }
        guard !size.isAlmostEqual(to: lastReportedViewportSize) else { return }

        lastReportedViewportSize = size
        viewportSizeDidChange?(size)
    }

    // MARK: - Space-hold pan

    override func keyDown(with event: NSEvent) {
        if event.charactersIgnoringModifiers == " " {
            if !isSpaceHeld { isSpaceHeld = true }
            return
        }
        super.keyDown(with: event)
    }

    override func keyUp(with event: NSEvent) {
        if event.charactersIgnoringModifiers == " " {
            isSpaceHeld = false
            return
        }
        super.keyUp(with: event)
    }

    override func resetCursorRects() {
        super.resetCursorRects()
        if isSpaceHeld {
            addCursorRect(bounds, cursor: .openHand)
        }
    }

    override var acceptsFirstResponder: Bool { true }
}

/// Clip view that centers the document view when it is smaller than the visible
/// area in either axis, instead of NSClipView's default corner pinning.
private final class CenteringClipView: NSClipView {
    override func constrainBoundsRect(_ proposedBounds: NSRect) -> NSRect {
        var rect = super.constrainBoundsRect(proposedBounds)
        guard let documentView else { return rect }
        let docFrame = documentView.frame
        if rect.width > docFrame.width {
            rect.origin.x = (docFrame.width - rect.width) / 2.0
        }
        if rect.height > docFrame.height {
            rect.origin.y = (docFrame.height - rect.height) / 2.0
        }
        return rect
    }
}

private extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}

private extension CGSize {
    func isAlmostEqual(to other: CGSize, accuracy: CGFloat = 0.5) -> Bool {
        abs(width - other.width) <= accuracy && abs(height - other.height) <= accuracy
    }
}
