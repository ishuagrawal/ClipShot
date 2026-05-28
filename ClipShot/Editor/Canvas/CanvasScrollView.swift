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

    /// Closure that fits the document into view. Held until the scroll view has a
    /// real laid-out size, then run exactly once (see `layout()`). Avoids fitting
    /// against a zero/placeholder size during the first render pass.
    private var pendingInitialFit: (() -> Void)?

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
        hasHorizontalScroller = true
        hasVerticalScroller = true
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

    override func layout() {
        super.layout()
        guard bounds.width > 0, bounds.height > 0, let fit = pendingInitialFit else { return }
        pendingInitialFit = nil
        fit()
    }

    // MARK: - Cmd+scroll zoom

    override func scrollWheel(with event: NSEvent) {
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
