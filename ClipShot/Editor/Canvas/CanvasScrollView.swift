import AppKit

/// NSScrollView subclass that provides:
/// - native pinch-to-zoom (via `allowsMagnification = true`)
/// - cmd+scroll zoom centered on the cursor
final class CanvasScrollView: NSScrollView {

    var viewportSizeDidChange: ((CGSize) -> Void)?
    var userInteractionDidStart: (() -> Void)?
    /// Fires whenever the zoom level changes (cmd-scroll, pinch, programmatic fit, or
    /// control bar), so the SwiftUI percentage readout can track it.
    var magnificationDidChange: ((CGFloat) -> Void)?

    /// Chrome occluding the viewport edges (top bar, bottom dock, inspector
    /// column). Fit-and-center operations aim for the unobstructed region inside
    /// these insets, so the document reads as filling and centered in the empty
    /// space the user actually sees.
    var occlusionInsets = NSEdgeInsets(top: 0, left: 0, bottom: 0, right: 0)

    /// Total chrome occlusion per axis.
    var occludedWidth: CGFloat { occlusionInsets.left + occlusionInsets.right }
    var occludedHeight: CGFloat { occlusionInsets.top + occlusionInsets.bottom }

    /// The image's frame in document (container) coordinates. Panning is clamped
    /// so this rect can never leave the viewport entirely.
    var imageKeepVisibleRect: CGRect {
        get { (contentView as? CenteringClipView)?.keepVisibleRect ?? .null }
        set { (contentView as? CenteringClipView)?.keepVisibleRect = newValue }
    }

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
        // Layer-backed throughout: panning then moves composited textures on the
        // GPU instead of redrawing views, which matters because the glass chrome
        // above re-samples this scroll view's content every frame.
        wantsLayer = true
        layerContentsRedrawPolicy = .onSetNeedsDisplay
        // Centering clip view so content smaller than the viewport is centered
        // instead of pinned to a corner.
        contentView = CenteringClipView()
        contentView.wantsLayer = true
        contentView.layerContentsRedrawPolicy = .onSetNeedsDisplay
        allowsMagnification = true
        minMagnification = ZoomMath.minMagnification
        maxMagnification = ZoomMath.maxMagnification
        magnification = 1
        hasHorizontalScroller = false
        hasVerticalScroller = false
        autohidesScrollers = true
        // Transparent: the SwiftUI StageBackdrop (dot grid + vignette) sits behind
        // this scroll view and provides the stage surface.
        drawsBackground = false
        contentView.drawsBackground = false
        horizontalScrollElasticity = .none
        verticalScrollElasticity = .none
        // Pinch / smart-magnify run through AppKit's live magnify; observe its end to
        // refresh the readout (cmd-scroll and programmatic paths notify directly).
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(liveMagnifyDidEnd),
            name: NSScrollView.didEndLiveMagnifyNotification,
            object: self
        )
        // Trackpad pans clamp back once the gesture lifts (momentum is handled
        // by the debounce in scrollWheel).
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(liveScrollDidEnd),
            name: NSScrollView.didEndLiveScrollNotification,
            object: self
        )
    }

    @objc private func liveMagnifyDidEnd() {
        magnificationDidChange?(magnification)
        enforceImageVisible()
    }

    @objc private func liveScrollDidEnd() {
        enforceImageVisible()
    }

    /// Set zoom from the control bar, centered on the current viewport center.
    func setMagnificationFromControl(_ value: CGFloat) {
        let clamped = value.clamped(to: minMagnification...maxMagnification)
        let center = CGPoint(x: contentView.bounds.midX, y: contentView.bounds.midY)
        setMagnification(clamped, centeredAt: center)
        magnificationDidChange?(clamped)
    }

    /// Register a fit to run once the scroll view has a valid size. If a size is
    /// already available the fit runs on the next layout pass immediately.
    func requestInitialFit(_ fit: @escaping () -> Void) {
        pendingInitialFit = fit
        needsLayout = true
    }

    func magnify(toFitCenteredOn rect: CGRect) {
        guard !rect.isNull, !rect.isEmpty else { return }
        var viewportSize = viewportSizeForFitting
        guard viewportSize.width > 0, viewportSize.height > 0 else { return }
        viewportSize.width = max(1, viewportSize.width - occludedWidth)
        viewportSize.height = max(1, viewportSize.height - occludedHeight)

        let targetMagnification = Self.fitMagnification(
            for: rect,
            in: viewportSize,
            limits: minMagnification...maxMagnification
        )
        let center = CGPoint(x: rect.midX, y: rect.midY)

        setMagnification(targetMagnification, centeredAt: center)
        layoutSubtreeIfNeeded()
        // Putting the fit center in the middle of the unobstructed region means
        // centering the viewport on a document point offset by half the occlusion
        // imbalance per axis (converted to document points; the document view is
        // flipped, so +y is downward and a bottom-heavy occlusion pushes up).
        let shifted = CGPoint(
            x: center.x + (occlusionInsets.right - occlusionInsets.left) / 2 / targetMagnification,
            y: center.y + (occlusionInsets.bottom - occlusionInsets.top) / 2 / targetMagnification
        )
        centerDocumentPoint(shifted)
        magnificationDidChange?(targetMagnification)
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
            // The scrolling engine animates toward its own target and overrides
            // mid-gesture corrections, so the keep-image-visible clamp runs once
            // events stop arriving (covers momentum and legacy wheel scrolls;
            // trackpad gesture-end is covered by didEndLiveScroll).
            scheduleKeepVisibleEnforcement()
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
        magnificationDidChange?(newMag)
    }

    override func magnify(with event: NSEvent) {
        userInteractionDidStart?()
        super.magnify(with: event)
        magnificationDidChange?(magnification)
    }

    override func smartMagnify(with event: NSEvent) {
        userInteractionDidStart?()
        super.smartMagnify(with: event)
        magnificationDidChange?(magnification)
    }

    private var keepVisibleEnforceTimer: Timer?

    /// Debounce: fires shortly after the last scroll event, when the scrolling
    /// engine has settled enough for a programmatic correction to stick.
    private func scheduleKeepVisibleEnforcement() {
        keepVisibleEnforceTimer?.invalidate()
        keepVisibleEnforceTimer = Timer.scheduledTimer(
            timeInterval: 0.15,
            target: self,
            selector: #selector(enforceImageVisibleNow),
            userInfo: nil,
            repeats: false
        )
    }

    @objc private func enforceImageVisibleNow() {
        enforceImageVisible()
    }

    /// Snap the viewport back so the image overlaps the UNOCCLUDED region (the
    /// part of the canvas not covered by the top bar, dock, or inspector) by at
    /// least ~96 view points on each axis. A sliver at the raw viewport edge
    /// would hide under the floating chrome and read as "image gone".
    private func enforceImageVisible() {
        guard let clip = contentView as? CenteringClipView else { return }
        let keep = clip.keepVisibleRect
        guard !keep.isNull, !keep.isEmpty, magnification > 0,
              clip.bounds.width > 0, clip.bounds.height > 0 else { return }

        let scale = 1 / magnification   // view points → document points
        var visible = clip.bounds
        visible.origin.x += occlusionInsets.left * scale
        visible.origin.y += occlusionInsets.top * scale
        visible.size.width -= occludedWidth * scale
        visible.size.height -= occludedHeight * scale
        guard visible.width > 0, visible.height > 0 else { return }

        let peekX = min(96 * scale, keep.width / 2)
        let peekY = min(96 * scale, keep.height / 2)
        let dx = visible.origin.x
            .clamped(to: (keep.minX + peekX - visible.width)...(keep.maxX - peekX))
            - visible.origin.x
        let dy = visible.origin.y
            .clamped(to: (keep.minY + peekY - visible.height)...(keep.maxY - peekY))
            - visible.origin.y
        guard dx != 0 || dy != 0 else { return }

        let target = CGPoint(x: clip.bounds.origin.x + dx, y: clip.bounds.origin.y + dy)
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.22
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            context.allowsImplicitAnimation = true
            clip.animator().setBoundsOrigin(target)
            reflectScrolledClipView(clip)
        }
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

    override var acceptsFirstResponder: Bool { true }
}

/// Clip view that centers the document view when it is smaller than the visible
/// area in either axis, instead of NSClipView's default corner pinning.
private final class CenteringClipView: NSClipView {
    /// See `CanvasScrollView.imageKeepVisibleRect`.
    var keepVisibleRect: CGRect = .null

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
