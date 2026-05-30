import AppKit

/// Transparent view layered above the canvas overlay. It captures only annotation
/// tool interactions; non-drawing tools and space-pan fall through to the scroll view.
@MainActor
final class CanvasInteractionView: NSView {

    weak var state: EditorState?
    weak var scrollView: CanvasScrollView?
    var onEditText: ((Annotation) -> Void)?
    var effectiveCrop: CGRect = .zero

    private var moveStartPoint: CGPoint?
    private var isMoving = false

    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }

    private var shouldCapture: Bool {
        guard let state, scrollView?.isSpaceHeld != true else { return false }
        switch state.activeTool {
        case .select, .arrow, .rectangle, .text:
            return true
        case .padding, .background, .blur:
            return false
        }
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        shouldCapture ? super.hitTest(point) : nil
    }

    override func resetCursorRects() {
        super.resetCursorRects()
        guard let state else { return }

        let cursor: NSCursor
        switch state.activeTool {
        case .arrow, .rectangle:
            cursor = .crosshair
        case .text:
            cursor = .iBeam
        default:
            cursor = .arrow
        }
        addCursorRect(bounds, cursor: cursor)
    }

    override func mouseDown(with event: NSEvent) {
        guard let state else {
            super.mouseDown(with: event)
            return
        }
        window?.makeFirstResponder(self)
        let point = documentPoint(for: event)

        if event.clickCount == 2, (state.activeTool == .select || state.activeTool == .text) {
            if let id = state.annotationID(at: point),
               let annotation = state.document.annotations.first(where: { $0.id == id }),
               case .text = annotation.kind {
                state.selectedAnnotationID = id
                onEditText?(annotation)
                return
            }
        }

        if state.activeTool.isDrawTool {
            if state.activeTool == .text {
                state.beginDraw(at: point)
                if let committed = state.commitDraw() {
                    onEditText?(committed)
                }
            } else {
                state.beginDraw(at: point)
            }
            return
        }

        state.selectAnnotation(at: point)
        if state.selectedAnnotationID != nil {
            moveStartPoint = point
            state.beginMoveSelected()
            isMoving = true
        }
    }

    override func mouseDragged(with event: NSEvent) {
        guard let state else { return }
        let point = documentPoint(for: event)
        let shift = event.modifierFlags.contains(.shift)

        if state.activeTool.isDrawTool, state.activeTool != .text {
            state.updateDraw(to: point, shiftSnap: shift)
        } else if isMoving, let start = moveStartPoint {
            state.moveSelected(by: CGSize(width: point.x - start.x, height: point.y - start.y))
        }
    }

    override func mouseUp(with event: NSEvent) {
        guard let state else { return }
        if state.activeTool.isDrawTool, state.activeTool != .text {
            _ = state.commitDraw()
        } else if isMoving {
            state.commitMoveSelected()
        }
        isMoving = false
        moveStartPoint = nil
    }

    override func keyDown(with event: NSEvent) {
        guard let state else {
            super.keyDown(with: event)
            return
        }

        if event.charactersIgnoringModifiers == " " {
            if scrollView?.isSpaceHeld != true {
                scrollView?.isSpaceHeld = true
                window?.invalidateCursorRects(for: self)
            }
            return
        }

        switch event.keyCode {
        case 53:
            state.cancelDraw()
            state.deselect()
        case 51, 117:
            state.deleteSelectedAnnotation()
        default:
            super.keyDown(with: event)
        }
    }

    override func keyUp(with event: NSEvent) {
        if event.charactersIgnoringModifiers == " " {
            scrollView?.isSpaceHeld = false
            window?.invalidateCursorRects(for: self)
            return
        }
        super.keyUp(with: event)
    }

    private func documentPoint(for event: NSEvent) -> CGPoint {
        let viewPoint = convert(event.locationInWindow, from: nil)
        return CanvasGeometry.documentPoint(fromImagePixel: viewPoint, effectiveCrop: effectiveCrop)
    }
}
