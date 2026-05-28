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

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        configure()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        configure()
    }

    private func configure() {
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
        let pointInView = convert(event.locationInWindow, from: nil)
        setMagnification(newMag, centeredAt: pointInView)
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

private extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
