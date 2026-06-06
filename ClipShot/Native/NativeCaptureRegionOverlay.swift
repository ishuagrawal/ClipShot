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
            let panel = NSPanel(
                contentRect: screen.frame,
                styleMask: [.borderless, .nonactivatingPanel],
                backing: .buffered,
                defer: false
            )
            panel.backgroundColor = .clear
            panel.isOpaque = false
            panel.hasShadow = false
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

private final class NativeCaptureRegionView: NSView {
    private let displayID: CGDirectDisplayID
    private let completion: (NativeCaptureRegion?) -> Void
    private var startPoint: CGPoint?
    private var currentPoint: CGPoint?
    private var didDrag = false

    /// Pointer travel (points) past which a press counts as a drag rather than a
    /// click. Below this the press is a click → whole-window capture; at or above
    /// it the user is selecting a region, even a small one.
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

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 {
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
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        currentPoint = point

        // A pure click (no real drag) captures the whole window under the cursor.
        guard didDrag else {
            completion(NativeCaptureRegion(
                displayID: displayID,
                sourceRect: CGRect(x: point.x, y: bounds.height - point.y, width: 1, height: 1),
                kind: .windowAtPoint
            ))
            return
        }

        // The user dragged: this is a region selection, even a small one. Too
        // tiny to be useful is a cancel, never a whole-window capture.
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
        guard let rect = selectionRect, rect.width > 1 || rect.height > 1 else { return }

        NSColor.black.withAlphaComponent(0.24).setFill()
        bounds.fill()

        if let context = NSGraphicsContext.current?.cgContext {
            context.saveGState()
            context.clear(rect)
            context.restoreGState()
        }

        NSColor.systemBlue.withAlphaComponent(0.18).setFill()
        rect.fill()

        let path = NSBezierPath(rect: rect)
        path.lineWidth = 2
        NSColor.systemBlue.setStroke()
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
