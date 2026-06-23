import AppKit

struct NativeCaptureRegion: Sendable {
    enum Kind: Sendable {
        case rect            // drag selection
        case windowAtPoint   // single click; sourceRect.origin is the click point
    }

    let displayID: CGDirectDisplayID
    let sourceRect: CGRect   // display-local, top-left origin, points
    var kind: Kind = .rect
}

@MainActor
final class NativeCaptureRegionOverlay {
    private var windows: [NSWindow] = []
    private var completion: ((NativeCaptureRegion?) -> Void)?

    func present(completion: @escaping (NativeCaptureRegion?) -> Void) {
        cancel()
        self.completion = completion

        for screen in NSScreen.screens {
            guard let displayID = screen.displayID else { continue }
            let panel = NativeCapturePanel(
                contentRect: screen.frame,
                styleMask: [.borderless, .nonactivatingPanel],
                backing: .buffered,
                defer: false
            )
            panel.backgroundColor = .clear
            panel.isOpaque = false
            panel.hasShadow = false
            // Prevent the capture overlay itself from appearing in screenshots.
            panel.sharingType = .none
            panel.level = .screenSaver
            panel.animationBehavior = .none
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
            panel.ignoresMouseEvents = false
            panel.acceptsMouseMovedEvents = true

            let selectionView = NativeCaptureRegionView(displayID: displayID) { [weak self] region in
                self?.finish(region)
            }
            selectionView.frame = CGRect(origin: .zero, size: screen.frame.size)
            panel.contentView = selectionView
            panel.makeKeyAndOrderFront(nil)
            windows.append(panel)
        }
    }

    private func finish(_ region: NativeCaptureRegion?) {
        let callback = completion
        completion = nil
        for window in windows {
            // Restore the hidden hardware cursor even if the mouse never exited.
            (window.contentView as? NativeCaptureRegionView)?.showHardwareCursor()
            window.orderOut(nil)
        }
        windows.removeAll()

        guard region != nil else {
            callback?(nil)
            return
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
            callback?(region)
        }
    }

    private func cancel() {
        guard !windows.isEmpty || completion != nil else { return }
        finish(nil)
    }
}

private final class NativeCapturePanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

private final class NativeCaptureRegionView: NSView {
    private let displayID: CGDirectDisplayID
    private let completion: (NativeCaptureRegion?) -> Void
    private var startPoint: CGPoint?
    private var currentPoint: CGPoint?
    private var hoverPoint: CGPoint?
    private var didDrag = false
    private var done = false
    private var cursorHidden = false

    /// Drawn crosshair geometry (points): arm length and center gap on each side.
    private let crosshairArm: CGFloat = 10
    private let crosshairGap: CGFloat = 3

    /// Pointer travel (points) past which a press is a region drag; below it,
    /// a click → whole-window capture.
    private let dragSlop: CGFloat = 4

    init(displayID: CGDirectDisplayID, completion: @escaping (NativeCaptureRegion?) -> Void) {
        self.displayID = displayID
        self.completion = completion
        super.init(frame: .zero)
        wantsLayer = true
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var acceptsFirstResponder: Bool { true }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        window?.makeFirstResponder(self)
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        for area in trackingAreas { removeTrackingArea(area) }
        addTrackingArea(NSTrackingArea(
            rect: bounds,
            options: [.activeAlways, .mouseMoved, .mouseEnteredAndExited, .inVisibleRect],
            owner: self,
            userInfo: nil
        ))
    }

    override func mouseEntered(with event: NSEvent) { moveHover(to: convert(event.locationInWindow, from: nil)) }
    override func mouseMoved(with event: NSEvent) { moveHover(to: convert(event.locationInWindow, from: nil)) }
    override func mouseExited(with event: NSEvent) { showHardwareCursor(); setHover(nil) }

    // A background (non-active) app can't reliably own the hardware cursor, so the
    // crosshair flickers. Hide the hardware cursor over the overlay and draw it.
    private func hideHardwareCursor() {
        guard !cursorHidden, !done else { return }
        CGDisplayHideCursor(CGMainDisplayID())
        cursorHidden = true
    }

    func showHardwareCursor() {
        guard cursorHidden else { return }
        CGDisplayShowCursor(CGMainDisplayID())
        cursorHidden = false
    }

    private func moveHover(to point: CGPoint) {
        hideHardwareCursor()
        setHover(point)
    }

    /// Repaints only the old and new crosshair footprints, not the full-screen view.
    private func setHover(_ point: CGPoint?) {
        if let old = hoverPoint { setNeedsDisplay(crosshairRect(around: old)) }
        hoverPoint = point
        if let point { setNeedsDisplay(crosshairRect(around: point)) }
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 {
            done = true
            showHardwareCursor()
            completion(nil)
        } else {
            super.keyDown(with: event)
        }
    }

    override func mouseDown(with event: NSEvent) {
        startPoint = convert(event.locationInWindow, from: nil)
        currentPoint = startPoint
        didDrag = false
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        currentPoint = point
        if let startPoint, hypot(point.x - startPoint.x, point.y - startPoint.y) >= dragSlop {
            didDrag = true
        }
        hideHardwareCursor()
        hoverPoint = point
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        currentPoint = point
        done = true
        showHardwareCursor()

        // A pure click (no real drag) captures the whole window under the cursor.
        guard didDrag else {
            completion(NativeCaptureRegion(
                displayID: displayID,
                sourceRect: CGRect(x: point.x, y: bounds.height - point.y, width: 1, height: 1),
                kind: .windowAtPoint
            ))
            return
        }

        // Dragged: region selection (even small). Too tiny to use = cancel.
        guard let rect = selectionRect, rect.width >= dragSlop, rect.height >= dragSlop else {
            completion(nil)
            return
        }

        completion(NativeCaptureRegion(
            displayID: displayID,
            sourceRect: CGRect(
                x: rect.minX,
                y: bounds.height - rect.maxY,
                width: rect.width,
                height: rect.height
            ),
            kind: .rect
        ))
    }

    override func draw(_ dirtyRect: NSRect) {
        if let rect = selectionRect, rect.width > 1 || rect.height > 1 {
            NSColor.white.withAlphaComponent(0.18).setFill()
            rect.fill()

            let path = NSBezierPath(rect: rect)
            path.lineWidth = 1
            NSColor.white.withAlphaComponent(0.9).setStroke()
            path.stroke()
        }

        if let point = hoverPoint, !done {
            drawCrosshair(at: point)
        }
    }

    private func crosshairRect(around point: CGPoint) -> CGRect {
        let reach = crosshairArm + crosshairGap + 2
        return CGRect(x: point.x - reach, y: point.y - reach, width: reach * 2, height: reach * 2)
    }

    private func drawCrosshair(at p: CGPoint) {
        let path = NSBezierPath()
        path.move(to: CGPoint(x: p.x - crosshairGap - crosshairArm, y: p.y))
        path.line(to: CGPoint(x: p.x - crosshairGap, y: p.y))
        path.move(to: CGPoint(x: p.x + crosshairGap, y: p.y))
        path.line(to: CGPoint(x: p.x + crosshairGap + crosshairArm, y: p.y))
        path.move(to: CGPoint(x: p.x, y: p.y - crosshairGap - crosshairArm))
        path.line(to: CGPoint(x: p.x, y: p.y - crosshairGap))
        path.move(to: CGPoint(x: p.x, y: p.y + crosshairGap))
        path.line(to: CGPoint(x: p.x, y: p.y + crosshairGap + crosshairArm))

        path.lineWidth = 3
        NSColor.white.withAlphaComponent(0.9).setStroke()
        path.stroke()
        path.lineWidth = 1
        NSColor.black.withAlphaComponent(0.85).setStroke()
        path.stroke()
    }

    private var selectionRect: CGRect? {
        guard let startPoint, let currentPoint else { return nil }
        return CGRect(
            x: min(startPoint.x, currentPoint.x),
            y: min(startPoint.y, currentPoint.y),
            width: abs(currentPoint.x - startPoint.x),
            height: abs(currentPoint.y - startPoint.y)
        )
    }
}

private extension NSScreen {
    var displayID: CGDirectDisplayID? {
        let key = NSDeviceDescriptionKey("NSScreenNumber")
        guard let number = deviceDescription[key] as? NSNumber else { return nil }
        return CGDirectDisplayID(number.uint32Value)
    }
}
