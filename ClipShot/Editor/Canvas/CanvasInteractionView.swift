import AppKit

/// Transparent view layered above the canvas overlay. It captures annotation
/// interactions and drawing tool gestures; empty non-drawing tools and space-pan
/// fall through to the scroll view.
@MainActor
final class CanvasInteractionView: NSView {

    private nonisolated static let textBorderHaloOutset: CGFloat = 3
    private nonisolated static let textBorderOuterHitTolerance: CGFloat = 10
    private nonisolated static let textBorderInnerHitTolerance: CGFloat = 5
    private nonisolated static let textSelectionMinimumHitSize: CGFloat = 32
    private nonisolated static let selectionDragActivationDistance: CGFloat = 3
    private nonisolated static let shapeDragHitTolerance: CGFloat = 10
    private nonisolated static let keyboardNudgeDistance: CGFloat = 8
    private nonisolated static let resizeHandleHitRadius: CGFloat = 9

    weak var state: EditorState? {
        didSet { invalidateCursorRectsIfPossible() }
    }
    weak var scrollView: CanvasScrollView?
    /// Customizable keyboard shortcuts (tool switches, copy/save, zoom, undo…).
    /// Handled here in the responder chain so unclaimed keys never reach
    /// `super`/the key-equivalent beep.
    var shortcutActions: [ShortcutCommand: () -> Void] = [:]
    var onEditText: ((Annotation) -> Void)?
    var onCommitActiveText: (() -> Bool)?
    var onHoverAnnotationChanged: ((UUID?) -> Void)?
    /// Fires true once a selected annotation actually starts moving/resizing and
    /// false on release, so the overlay can hide resize handles mid-drag.
    var onDraggingChanged: ((Bool) -> Void)?
    var editingTextAnnotation: Annotation? {
        didSet { invalidateCursorRectsIfPossible() }
    }
    var baseSelection: CGRect = .zero {
        didSet {
            if oldValue != baseSelection {
                invalidateCursorRectsIfPossible()
            }
        }
    }
    var imageSpaceOrigin: CGPoint = .zero {
        didSet {
            if oldValue != imageSpaceOrigin {
                invalidateCursorRectsIfPossible()
            }
        }
    }

    /// Physical canvas magnification. Resize-handle hit targets divide by it so
    /// they stay a constant on-screen size regardless of zoom.
    var zoomScale: CGFloat = 1 {
        didSet {
            if oldValue != zoomScale { invalidateCursorRectsIfPossible() }
        }
    }

    private var moveStartPoint: CGPoint?
    private var movingTextDraftID: UUID?
    private var isMoving = false
    private var didMoveSelected = false
    private var activeResizeHandle: ResizeHandle?
    private var hoveredAnnotationID: UUID? {
        didSet {
            guard oldValue != hoveredAnnotationID else { return }
            onHoverAnnotationChanged?(hoveredAnnotationID)
        }
    }
    private var cursorTrackingArea: NSTrackingArea?

    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }

    func requestKeyboardFocus() {
        window?.makeFirstResponder(self)
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        // Own every pointer interaction whenever a tool is active. Pan and zoom arrive as
        // scroll-wheel / pinch events, which bypass hit-testing, so there is nothing to fall
        // through to. The old fall-through path mis-converted `point` (it is in superview
        // space, not image-pixel space), which broke annotation dragging once the canvas was
        // offset by the zoom-to-selection fit. `mouseDown` decides what the click means.
        // An active text field is a later sibling (higher z-order) and still wins its own area.
        guard let state, !state.previewingOriginal else { return nil }
        return self
    }

    override func resetCursorRects() {
        super.resetCursorRects()
        guard let state else { return }

        switch state.activeTool {
        case .arrow, .line, .rectangle:
            addCursorRect(bounds, cursor: .crosshair)
        case .text:
            addCursorRect(bounds, cursor: .iBeam)
        case .select:
            addTextBorderCursorRects()
            addShapeCursorRects()
            addResizeHandleCursorRects()
        case .padding, .background, .blur:
            break
        }
    }

    override func updateTrackingAreas() {
        if let cursorTrackingArea {
            removeTrackingArea(cursorTrackingArea)
        }

        let trackingArea = NSTrackingArea(
            rect: .zero,
            options: [.activeInKeyWindow, .cursorUpdate, .inVisibleRect, .mouseMoved],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(trackingArea)
        cursorTrackingArea = trackingArea
        super.updateTrackingAreas()
    }

    override func cursorUpdate(with event: NSEvent) {
        applyCursor(for: event)
    }

    override func mouseMoved(with event: NSEvent) {
        applyCursor(for: event)
        super.mouseMoved(with: event)
    }

    override func mouseDown(with event: NSEvent) {
        guard let state else {
            super.mouseDown(with: event)
            return
        }
        requestKeyboardFocus()
        let point = documentPoint(for: event)

        switch state.activeTool {
        case .select, .padding, .background:
            if let handle = resizeHandleHit(at: point) {
                state.activeTool = .select
                state.beginResize(handle: handle)
                activeResizeHandle = handle
                isMoving = false
                return
            }
            if let annotation = annotationInteractionTarget(at: point) {
                if event.clickCount >= 2 {
                    activateEditingTool(for: annotation)
                    return
                }
                beginMove(annotation, at: point)
                return
            }
            state.deselect()

        case .text:
            let hadActiveText = onCommitActiveText?() ?? false
            guard !hadActiveText || state.activeTool == .text else { return }
            if let draft = state.beginTextDraft(at: point) {
                onEditText?(draft)
            }

        case .arrow, .line, .rectangle, .blur:
            state.beginDraw(at: point)
        }
    }

    override func mouseDragged(with event: NSEvent) {
        guard let state else { return }
        let point = documentPoint(for: event)
        let shift = event.modifierFlags.contains(.shift)

        if activeResizeHandle != nil {
            onDraggingChanged?(true)
            state.resizeSelected(to: point, shiftLock: shift)
        } else if isMoving, let start = moveStartPoint {
            let delta = CGSize(width: point.x - start.x, height: point.y - start.y)
            if !didMoveSelected,
               hypot(delta.width, delta.height) < Self.selectionDragActivationDistance {
                return
            }
            if !didMoveSelected { onDraggingChanged?(true) }
            didMoveSelected = true
            if movingTextDraftID != nil {
                state.moveTextDraft(by: delta)
            } else {
                state.moveSelected(by: delta)
            }
        } else if state.activeTool == .arrow || state.activeTool == .line || state.activeTool == .rectangle {
            state.updateDraw(to: point, shiftSnap: shift)
        }
    }

    override func mouseUp(with event: NSEvent) {
        guard let state else { return }

        if activeResizeHandle != nil {
            state.commitResizeSelected()
            invalidateCursorRectsIfPossible()
        } else if isMoving {
            if movingTextDraftID != nil {
                state.commitMoveTextDraft()
            } else {
                state.commitMoveSelected()
            }
            invalidateCursorRectsIfPossible()
        } else if state.activeTool == .arrow || state.activeTool == .line || state.activeTool == .rectangle {
            if state.commitDraw() != nil {
                invalidateCursorRectsIfPossible()
            }
        }
        isMoving = false
        didMoveSelected = false
        movingTextDraftID = nil
        moveStartPoint = nil
        activeResizeHandle = nil
        onDraggingChanged?(false)
    }

    /// Command-key combos route through here (the key-equivalent phase), so
    /// claiming them returns true and avoids the system "unhandled key" beep.
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if runShortcut(for: event) { return true }
        return super.performKeyEquivalent(with: event)
    }

    override func keyDown(with event: NSEvent) {
        // Bare-key shortcuts (tools, preview) run regardless of preview mode.
        if runShortcut(for: event) { return }
        guard let state else {
            super.keyDown(with: event)
            return
        }
        guard !state.previewingOriginal else {
            super.keyDown(with: event)
            return
        }

        if let delta = Self.keyboardNudgeDelta(for: event) {
            if state.activeTool == .select {
                state.nudgeSelected(by: delta)
            }
            return
        }

        super.keyDown(with: event)
    }

    /// Runs the first shortcut whose binding matches, unless a text field is being
    /// edited (so bare letters and ⌘C/⌘V keep working in fields).
    private func runShortcut(for event: NSEvent) -> Bool {
        guard window?.firstResponderAcceptsTextInput != true else { return false }
        let store = ShortcutStore.shared
        for (command, action) in shortcutActions where store.binding(for: command).matches(event) {
            action()
            return true
        }
        return false
    }

    private func documentPoint(for event: NSEvent) -> CGPoint {
        let viewPoint = convert(event.locationInWindow, from: nil)
        return CanvasGeometry.annotationPoint(
            fromCanvasPoint: viewPoint,
            canvasOriginInImage: imageSpaceOrigin,
            baseSelection: baseSelection
        )
    }

    /// Single-letter tool shortcuts (V/A/L/R/T), matching the tool-rail tooltips.
    /// Only fires with no modifiers so it never shadows menu commands; text editing
    /// is unaffected because the in-canvas text editor is first responder then.
    nonisolated static func keyboardNudgeDelta(for event: NSEvent) -> CGSize? {
        let ignoredModifiers: NSEvent.ModifierFlags = [.command, .control, .option]
        guard event.modifierFlags.intersection(ignoredModifiers).isEmpty else { return nil }

        switch event.keyCode {
        case 123:
            return CGSize(width: -keyboardNudgeDistance, height: 0)
        case 124:
            return CGSize(width: keyboardNudgeDistance, height: 0)
        case 125:
            return CGSize(width: 0, height: keyboardNudgeDistance)
        case 126:
            return CGSize(width: 0, height: -keyboardNudgeDistance)
        default:
            return nil
        }
    }

    private func selectableAnnotation(at point: CGPoint) -> Annotation? {
        guard let state else { return nil }

        return displayAnnotations(for: state).reversed().first { annotation in
            if case .text = annotation.kind {
                return textBorderContains(point, annotation: annotation)
                    || textSelectionContains(point, annotation: annotation)
            }

            return AnnotationGeometry.hitTest(
                annotation.kind,
                point: point,
                tolerance: Self.shapeDragHitTolerance
            )
        }
    }

    private func annotationInteractionTarget(at point: CGPoint) -> Annotation? {
        guard let state else { return nil }

        switch state.activeTool {
        case .select, .padding, .background:
            return selectableAnnotation(at: point)
        case .arrow, .line, .rectangle, .text, .blur:
            return nil
        }
    }

    private func textBorderContains(_ point: CGPoint, annotation: Annotation) -> Bool {
        guard case .text = annotation.kind else { return false }

        return textBorderHitFrames(for: annotation).contains { $0.containsIncludingMaxEdges(point) }
    }

    private func textSelectionContains(_ point: CGPoint, annotation: Annotation) -> Bool {
        guard case .text = annotation.kind else { return false }

        return textSelectionHitFrame(for: annotation).containsIncludingMaxEdges(point)
    }

    private func addTextBorderCursorRects() {
        guard let state else { return }

        for annotation in displayAnnotations(for: state) {
            guard case .text = annotation.kind else { continue }
            if editingTextAnnotation?.id != annotation.id, state.activeTool == .select {
                addCursorRect(
                    viewFrame(forDocumentFrame: textSelectionHitFrame(for: annotation)),
                    cursor: .openHand
                )
            }
            for frame in textBorderHitFrames(for: annotation) {
                addCursorRect(viewFrame(forDocumentFrame: frame), cursor: .openHand)
            }
        }
    }

    /// The resize handle under `point`, in annotation coords. Picks the closest
    /// within a zoom-independent screen radius. Only the selected annotation has
    /// handles.
    private func resizeHandleHit(at point: CGPoint) -> ResizeHandle? {
        guard let state, let selected = state.selectedAnnotation else { return nil }
        let tolerance = Self.resizeHandleHitRadius / max(zoomScale, 0.0001)
        var best: (handle: ResizeHandle, distance: CGFloat)?
        for (handle, anchor) in AnnotationGeometry.resizeHandles(selected.kind) {
            let d = hypot(point.x - anchor.x, point.y - anchor.y)
            if d <= tolerance, best == nil || d < best!.distance {
                best = (handle, d)
            }
        }
        return best?.handle
    }

    private func addResizeHandleCursorRects() {
        guard let state, let selected = state.selectedAnnotation else { return }
        let r = Self.resizeHandleHitRadius / max(zoomScale, 0.0001)
        for (handle, anchor) in AnnotationGeometry.resizeHandles(selected.kind) {
            let docFrame = CGRect(x: anchor.x - r, y: anchor.y - r, width: r * 2, height: r * 2)
            addCursorRect(viewFrame(forDocumentFrame: docFrame), cursor: Self.cursor(for: handle))
        }
    }

    private nonisolated static func cursor(for handle: ResizeHandle) -> NSCursor {
        switch handle {
        case .left, .right: return .resizeLeftRight
        case .top, .bottom: return .resizeUpDown
        case .topLeft, .bottomRight, .scaleTopLeft, .scaleBottomRight: return diagonalResizeCursor(mirrored: false)
        case .topRight, .bottomLeft, .scaleTopRight, .scaleBottomLeft: return diagonalResizeCursor(mirrored: true)
        case .start, .end, .curve: return .crosshair
        }
    }

    private func addShapeCursorRects() {
        guard let state else { return }

        for annotation in state.document.annotations {
            guard !annotation.kind.isText else { continue }
            addCursorRect(
                viewFrame(
                    forDocumentFrame: AnnotationGeometry
                        .boundingBox(annotation.kind)
                        .insetBy(dx: -Self.shapeDragHitTolerance, dy: -Self.shapeDragHitTolerance)
                ),
                cursor: .openHand
            )
        }
    }

    private func displayAnnotations(for state: EditorState) -> [Annotation] {
        var annotations = state.document.annotations.map { annotation in
            if let editingTextAnnotation, editingTextAnnotation.id == annotation.id {
                return editingTextAnnotation
            }
            return annotation
        }

        if let draft = state.inProgressTextDraft,
           !annotations.contains(where: { $0.id == draft.id }) {
            if let editingTextAnnotation, editingTextAnnotation.id == draft.id {
                annotations.append(editingTextAnnotation)
            } else {
                annotations.append(draft)
            }
        }

        return annotations
    }

    private func textBorderHitFrames(for annotation: Annotation) -> [CGRect] {
        let frame = AnnotationGeometry
            .boundingBox(annotation.kind)
            .insetBy(dx: -Self.textBorderHaloOutset, dy: -Self.textBorderHaloOutset)
        let outer = Self.textBorderOuterHitTolerance
        let inner = Self.textBorderInnerHitTolerance

        return [
            CGRect(
                x: frame.minX - outer,
                y: frame.minY - outer,
                width: frame.width + outer * 2,
                height: outer + inner
            ),
            CGRect(
                x: frame.minX - outer,
                y: frame.maxY - inner,
                width: frame.width + outer * 2,
                height: outer + inner
            ),
            CGRect(
                x: frame.minX - outer,
                y: frame.minY - inner,
                width: outer + inner,
                height: frame.height + inner * 2
            ),
            CGRect(
                x: frame.maxX - inner,
                y: frame.minY - inner,
                width: outer + inner,
                height: frame.height + inner * 2
            )
        ]
    }

    private func textSelectionHitFrame(for annotation: Annotation) -> CGRect {
        let frame = AnnotationGeometry
            .boundingBox(annotation.kind)
            .insetBy(dx: -Self.textBorderHaloOutset, dy: -Self.textBorderHaloOutset)
        let minSize = Self.textSelectionMinimumHitSize
        let width = max(frame.width, minSize)
        let height = max(frame.height, minSize)

        return CGRect(
            x: frame.midX - width / 2,
            y: frame.midY - height / 2,
            width: width,
            height: height
        )
    }

    private func viewFrame(forDocumentFrame frame: CGRect) -> CGRect {
        let origin = CanvasGeometry.canvasPoint(
            fromAnnotationPoint: frame.origin,
            canvasOriginInImage: imageSpaceOrigin,
            baseSelection: baseSelection
        )
        return CGRect(origin: origin, size: frame.size)
    }

    private func beginMove(_ annotation: Annotation, at point: CGPoint) {
        guard let state else { return }

        if state.inProgressTextDraft?.id == annotation.id {
            movingTextDraftID = annotation.id
            state.selectedAnnotationID = nil
            state.activeTool = .select
            state.documentPanel = .components
            moveStartPoint = point
            state.beginMoveTextDraft(id: annotation.id)
            isMoving = true
            didMoveSelected = false
            return
        }

        state.cancelDraw()
        movingTextDraftID = nil
        state.selectedAnnotationID = annotation.id
        state.activeTool = .select
        state.documentPanel = .components
        moveStartPoint = point
        state.beginMoveSelected()
        isMoving = true
        didMoveSelected = false
    }

    private func activateEditingTool(for annotation: Annotation) {
        guard let state else { return }

        if state.inProgressTextDraft?.id == annotation.id {
            state.selectedAnnotationID = nil
            state.activeTool = .select
            state.documentPanel = .components
            isMoving = false
            didMoveSelected = false
            movingTextDraftID = nil
            moveStartPoint = nil
            invalidateCursorRectsIfPossible()
            return
        }

        state.cancelDraw()
        state.selectedAnnotationID = annotation.id
        if case .text = annotation.kind {
            state.activeTool = .text
        } else {
            state.activeTool = .select
        }
        state.documentPanel = .components
        isMoving = false
        didMoveSelected = false
        moveStartPoint = nil
        invalidateCursorRectsIfPossible()

        if case .text = annotation.kind {
            onEditText?(annotation)
        }
    }

    private func invalidateCursorRectsIfPossible() {
        guard let window else { return }
        window.invalidateCursorRects(for: self)
        applyCursor(atWindowPoint: window.mouseLocationOutsideOfEventStream)
    }

    private func applyCursor(for event: NSEvent) {
        applyCursor(atWindowPoint: event.locationInWindow)
    }

    private func applyCursor(atWindowPoint windowPoint: CGPoint) {
        let viewPoint = convert(windowPoint, from: nil)
        guard bounds.contains(viewPoint) else {
            hoveredAnnotationID = nil
            return
        }

        let documentPoint = CanvasGeometry.annotationPoint(
            fromCanvasPoint: viewPoint,
            canvasOriginInImage: imageSpaceOrigin,
            baseSelection: baseSelection
        )

        if let handle = resizeHandleHit(at: documentPoint) {
            Self.cursor(for: handle).set()
            return
        }

        let annotation = annotationInteractionTarget(at: documentPoint)
        hoveredAnnotationID = annotation?.id

        if annotation != nil {
            NSCursor.openHand.set()
        } else {
            baseCursor.set()
        }
    }

    private var baseCursor: NSCursor {
        guard let state else { return .arrow }
        switch state.activeTool {
        case .arrow, .line, .rectangle:
            return .crosshair
        case .text:
            return .iBeam
        default:
            return .arrow
        }
    }

    // macOS has no public diagonal resize cursor, so draw a double-headed arrow.
    // Cached; only ever built/read on the main thread.
    nonisolated(unsafe) private static var diagNWSE: NSCursor?
    nonisolated(unsafe) private static var diagNESW: NSCursor?

    private nonisolated static func diagonalResizeCursor(mirrored: Bool) -> NSCursor {
        if mirrored, let c = diagNESW { return c }
        if !mirrored, let c = diagNWSE { return c }
        let selectorName = mirrored
            ? "_windowResizeNorthEastSouthWestCursor"
            : "_windowResizeNorthWestSouthEastCursor"
        let cursor = systemCursor(named: selectorName) ?? makeDiagonalResizeCursor(mirrored: mirrored)
        if mirrored { diagNESW = cursor } else { diagNWSE = cursor }
        return cursor
    }

    /// Resolve a built-in cursor exposed only as a private NSCursor class method.
    /// Returns nil if the selector is gone in a future OS, so callers fall back.
    private nonisolated static func systemCursor(named name: String) -> NSCursor? {
        let selector = NSSelectorFromString(name)
        guard NSCursor.responds(to: selector),
              let cursor = NSCursor.perform(selector)?.takeUnretainedValue() as? NSCursor else {
            return nil
        }
        return cursor
    }

    private nonisolated static func makeDiagonalResizeCursor(mirrored: Bool) -> NSCursor {
        let image = NSImage(size: NSSize(width: 24, height: 24))
        image.lockFocus()

        let a = NSPoint(x: 5, y: mirrored ? 19 : 5)
        let b = NSPoint(x: 19, y: mirrored ? 5 : 19)
        let angle = atan2(b.y - a.y, b.x - a.x)
        let head: CGFloat = 5

        let path = NSBezierPath()
        path.move(to: a)
        path.line(to: b)
        for (tip, dir) in [(a, angle), (b, angle + .pi)] {
            for delta in [CGFloat.pi * 0.8, -CGFloat.pi * 0.8] {
                path.move(to: tip)
                path.line(to: NSPoint(x: tip.x + cos(dir + delta) * head, y: tip.y + sin(dir + delta) * head))
            }
        }

        path.lineWidth = 4
        path.lineCapStyle = .round
        NSColor.white.setStroke()
        path.stroke()
        path.lineWidth = 2
        NSColor.black.setStroke()
        path.stroke()

        image.unlockFocus()
        return NSCursor(image: image, hotSpot: NSPoint(x: 12, y: 12))
    }
}

private extension Annotation.Kind {
    var isText: Bool {
        if case .text = self { return true }
        return false
    }
}

private extension CGRect {
    func containsIncludingMaxEdges(_ point: CGPoint) -> Bool {
        point.x >= minX
        && point.x <= maxX
        && point.y >= minY
        && point.y <= maxY
    }
}
