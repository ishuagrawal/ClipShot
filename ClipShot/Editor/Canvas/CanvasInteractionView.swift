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

    weak var state: EditorState? {
        didSet { invalidateCursorRectsIfPossible() }
    }
    weak var scrollView: CanvasScrollView?
    var onEditText: ((Annotation) -> Void)?
    var onCommitActiveText: (() -> Bool)?
    var onHoverAnnotationChanged: ((UUID?) -> Void)?
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

    private var moveStartPoint: CGPoint?
    private var movingTextDraftID: UUID?
    private var isMoving = false
    private var didMoveSelected = false
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
        guard state != nil else { return nil }
        return self
    }

    override func resetCursorRects() {
        super.resetCursorRects()
        guard let state else { return }

        switch state.activeTool {
        case .arrow, .rectangle:
            addCursorRect(bounds, cursor: .crosshair)
        case .text:
            addCursorRect(bounds, cursor: .iBeam)
        case .select:
            addTextBorderCursorRects()
            addShapeCursorRects()
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

        case .arrow, .rectangle, .blur:
            state.beginDraw(at: point)
        }
    }

    override func mouseDragged(with event: NSEvent) {
        guard let state else { return }
        let point = documentPoint(for: event)
        let shift = event.modifierFlags.contains(.shift)

        if isMoving, let start = moveStartPoint {
            let delta = CGSize(width: point.x - start.x, height: point.y - start.y)
            if !didMoveSelected,
               hypot(delta.width, delta.height) < Self.selectionDragActivationDistance {
                return
            }
            didMoveSelected = true
            if movingTextDraftID != nil {
                state.moveTextDraft(by: delta)
            } else {
                state.moveSelected(by: delta)
            }
        } else if state.activeTool == .arrow || state.activeTool == .rectangle {
            state.updateDraw(to: point, shiftSnap: shift)
        }
    }

    override func mouseUp(with event: NSEvent) {
        guard let state else { return }

        if isMoving {
            if movingTextDraftID != nil {
                state.commitMoveTextDraft()
            } else {
                state.commitMoveSelected()
            }
            invalidateCursorRectsIfPossible()
        } else if state.activeTool == .arrow || state.activeTool == .rectangle {
            if state.commitDraw() != nil {
                invalidateCursorRectsIfPossible()
            }
        }
        isMoving = false
        didMoveSelected = false
        movingTextDraftID = nil
        moveStartPoint = nil
    }

    override func keyDown(with event: NSEvent) {
        guard let state else {
            super.keyDown(with: event)
            return
        }

        if let delta = Self.keyboardNudgeDelta(for: event) {
            if state.activeTool == .select {
                state.nudgeSelected(by: delta)
            }
            return
        }

        if let tool = Self.toolShortcut(for: event) {
            state.selectCursorTool(tool)
            return
        }

        super.keyDown(with: event)
    }

    private func documentPoint(for event: NSEvent) -> CGPoint {
        let viewPoint = convert(event.locationInWindow, from: nil)
        return CanvasGeometry.annotationPoint(
            fromCanvasPoint: viewPoint,
            canvasOriginInImage: imageSpaceOrigin,
            baseSelection: baseSelection
        )
    }

    /// Single-letter tool shortcuts (V/A/R/T), matching the tool-rail tooltips.
    /// Only fires with no modifiers so it never shadows menu commands; text editing
    /// is unaffected because the in-canvas text editor is first responder then.
    nonisolated static func toolShortcut(for event: NSEvent) -> EditorTool? {
        guard event.modifierFlags.intersection([.command, .control, .option]).isEmpty,
              let chars = event.charactersIgnoringModifiers?.lowercased() else { return nil }
        switch chars {
        case "v": return .select
        case "a": return .arrow
        case "r": return .rectangle
        case "t": return .text
        default:  return nil
        }
    }

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
        case .arrow, .rectangle, .text, .blur:
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
        case .arrow, .rectangle:
            return .crosshair
        case .text:
            return .iBeam
        default:
            return .arrow
        }
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
