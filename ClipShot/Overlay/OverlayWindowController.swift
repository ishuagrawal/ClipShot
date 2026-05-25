import AppKit

@MainActor
final class OverlayWindowController: NSWindowController {
    var onMouseMoved: ((CGPoint) -> Void)?
    var onConfirm: (() -> Void)?
    var onCancel: (() -> Void)?
    var onCycle: (() -> Void)?

    private let screenFrame: CGRect
    private let overlayView: OverlayView

    init(screen: NSScreen) {
        screenFrame = screen.frame
        overlayView = OverlayView(screenFrame: screen.frame)

        let window = OverlayWindow(
            contentRect: screen.frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false,
            screen: screen
        )
        window.backgroundColor = .clear
        window.isOpaque = false
        window.hasShadow = false
        window.level = .screenSaver
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        window.ignoresMouseEvents = false
        window.acceptsMouseMovedEvents = true
        window.isReleasedWhenClosed = false
        window.contentView = overlayView
        window.setAccessibilityElement(false)
        overlayView.setAccessibilityElement(false)

        super.init(window: window)

        window.onMouseMoved = { [weak self] point in
            self?.onMouseMoved?(point)
        }
        window.onConfirm = { [weak self] in
            self?.onConfirm?()
        }
        window.onCancel = { [weak self] in
            self?.onCancel?()
        }
        window.onCycle = { [weak self] in
            self?.onCycle?()
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func show() {
        window?.setFrame(screenFrame, display: true)
        window?.makeKeyAndOrderFront(nil)
        window?.orderFrontRegardless()
    }

    func updateSelection(
        globalCocoaRect: CGRect?,
        allGlobalCocoaRects: [CGRect],
        label: String?,
        index: Int?,
        count: Int?
    ) {
        overlayView.updateSelection(
            globalCocoaRect: globalCocoaRect,
            allGlobalCocoaRects: allGlobalCocoaRects,
            label: label,
            index: index,
            count: count
        )
    }

    func closeOverlay() {
        close()
    }
}

private final class OverlayWindow: NSWindow {
    var onMouseMoved: ((CGPoint) -> Void)?
    var onConfirm: (() -> Void)?
    var onCancel: (() -> Void)?
    var onCycle: (() -> Void)?

    override var canBecomeKey: Bool {
        true
    }

    override var canBecomeMain: Bool {
        true
    }

    override func mouseMoved(with event: NSEvent) {
        onMouseMoved?(globalPoint(from: event))
    }

    override func mouseDragged(with event: NSEvent) {
        onMouseMoved?(globalPoint(from: event))
    }

    override func mouseDown(with event: NSEvent) {
        onConfirm?()
    }

    override func keyDown(with event: NSEvent) {
        switch event.keyCode {
        case 36, 76:
            onConfirm?()
        case 48:
            onCycle?()
        case 53:
            onCancel?()
        default:
            super.keyDown(with: event)
        }
    }

    private func globalPoint(from event: NSEvent) -> CGPoint {
        convertPoint(toScreen: event.locationInWindow)
    }
}
