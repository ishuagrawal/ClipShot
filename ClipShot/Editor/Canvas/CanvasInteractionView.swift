import AppKit

/// Transparent view layered above the canvas overlay. It captures annotation
/// interactions and drawing tool gestures; empty non-drawing tools and space-pan
/// fall through to the scroll view.
@MainActor
final class CanvasInteractionView: NSView {

    private nonisolated static let textBorderHaloOutset: CGFloat = 3
    private nonisolated static let textBorderOuterHitTolerance: CGFloat = 10
    private nonisolated static let textBorderInnerHitTolerance: CGFloat = 5
    private nonisolated static let selectionDragActivationDistance: CGFloat = 3
    private nonisolated static let shapeDragHitTolerance: CGFloat = 10
    private nonisolated static let keyboardNudgeDistance: CGFloat = 8

    weak var state: EditorState? {
        didSet { invalidateCursorRectsIfPossible() }
    }
    weak var scrollView: CanvasScrollView?
    var onEditText: ((Annotation) -> Void)?
    var editingTextAnnotation: Annotation? {
        didSet { invalidateCursorRectsIfPossible() }
    }
    var effectiveCrop: CGRect = .zero {
        didSet {
            if oldValue != effectiveCrop {
                invalidateCursorRectsIfPossible()
            }
        }
    }

    private var moveStartPoint: CGPoint?
    private var isMoving = false
    private var didMoveSelected = false
    private var cursorTrackingArea: NSTrackingArea?

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
        guard scrollView?.isSpaceHeld != true else { return nil }
        if shouldCapture {
            return super.hitTest(point)
        }

        let documentPoint = CanvasGeometry.documentPoint(fromImagePixel: point, effectiveCrop: effectiveCrop)
        return draggableAnnotation(at: documentPoint) == nil ? nil : self
    }

    override func resetCursorRects() {
        super.resetCursorRects()
        guard let state else { return }

        if shouldCapture {
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
        addTextBorderCursorRects()
        addRectCursorRects()
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
        window?.makeFirstResponder(self)
        let point = documentPoint(for: event)

        if let annotation = draggableAnnotation(at: point) {
            if event.clickCount >= 2 {
                activateEditingTool(for: annotation)
                return
            }
            beginMove(annotation, at: point)
            return
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
            didMoveSelected = false
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
            state.moveSelected(by: delta)
        } else if state.activeTool.isDrawTool, state.activeTool != .text {
            state.updateDraw(to: point, shiftSnap: shift)
        }
    }

    override func mouseUp(with event: NSEvent) {
        guard let state else { return }

        if isMoving {
            state.commitMoveSelected()
            invalidateCursorRectsIfPossible()
        } else if state.activeTool.isDrawTool, state.activeTool != .text {
            _ = state.commitDraw()
        }
        isMoving = false
        didMoveSelected = false
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

        if let delta = keyboardNudgeDelta(for: event) {
            if state.activeTool == .select {
                state.nudgeSelected(by: delta)
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

    private func keyboardNudgeDelta(for event: NSEvent) -> CGSize? {
        let ignoredModifiers: NSEvent.ModifierFlags = [.command, .control, .option]
        guard event.modifierFlags.intersection(ignoredModifiers).isEmpty else { return nil }

        switch event.keyCode {
        case 123:
            return CGSize(width: -Self.keyboardNudgeDistance, height: 0)
        case 124:
            return CGSize(width: Self.keyboardNudgeDistance, height: 0)
        case 125:
            return CGSize(width: 0, height: Self.keyboardNudgeDistance)
        case 126:
            return CGSize(width: 0, height: -Self.keyboardNudgeDistance)
        default:
            return nil
        }
    }

    private func textBorderAnnotation(at point: CGPoint) -> Annotation? {
        guard let state else { return nil }

        return displayAnnotations(for: state).reversed().first { annotation in
            return textBorderContains(point, annotation: annotation)
        }
    }

    private func inactiveTextBodyAnnotation(at point: CGPoint) -> Annotation? {
        guard let state else { return nil }

        return displayAnnotations(for: state).reversed().first { annotation in
            guard case .text = annotation.kind,
                  editingTextAnnotation?.id != annotation.id else {
                return false
            }

            return AnnotationGeometry.boundingBox(annotation.kind).containsIncludingMaxEdges(point)
        }
    }

    private func draggableTextAnnotation(at point: CGPoint) -> Annotation? {
        textBorderAnnotation(at: point) ?? inactiveTextBodyAnnotation(at: point)
    }

    private func shapeAnnotation(at point: CGPoint) -> Annotation? {
        guard let state else { return nil }

        return state.document.annotations.reversed().first { annotation in
            guard annotation.isDraggableShape else { return false }
            return AnnotationGeometry.hitTest(
                annotation.kind,
                point: point,
                tolerance: Self.shapeDragHitTolerance
            )
        }
    }

    private func draggableAnnotation(at point: CGPoint) -> Annotation? {
        draggableTextAnnotation(at: point) ?? shapeAnnotation(at: point)
    }

    private func textBorderContains(_ point: CGPoint, annotation: Annotation) -> Bool {
        guard case .text = annotation.kind else { return false }

        return textBorderHitFrames(for: annotation).contains { $0.containsIncludingMaxEdges(point) }
    }

    private func addTextBorderCursorRects() {
        guard let state, scrollView?.isSpaceHeld != true else { return }

        for annotation in displayAnnotations(for: state) {
            guard case .text = annotation.kind else { continue }
            if editingTextAnnotation?.id != annotation.id {
                addCursorRect(
                    viewFrame(forDocumentFrame: AnnotationGeometry.boundingBox(annotation.kind)),
                    cursor: .openHand
                )
            }
            for frame in textBorderHitFrames(for: annotation) {
                addCursorRect(viewFrame(forDocumentFrame: frame), cursor: .openHand)
            }
        }
    }

    private func addRectCursorRects() {
        guard let state, scrollView?.isSpaceHeld != true else { return }

        for annotation in state.document.annotations {
            guard case .rect = annotation.kind else { continue }
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
        state.document.annotations.map { annotation in
            if let editingTextAnnotation, editingTextAnnotation.id == annotation.id {
                return editingTextAnnotation
            }
            return annotation
        }
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

    private func viewFrame(forDocumentFrame frame: CGRect) -> CGRect {
        let origin = CanvasGeometry.imagePixel(
            fromDocumentPoint: frame.origin,
            effectiveCrop: effectiveCrop
        )
        return CGRect(origin: origin, size: frame.size)
    }

    private func beginMove(_ annotation: Annotation, at point: CGPoint) {
        guard let state else { return }

        state.cancelDraw()
        state.selectedAnnotationID = annotation.id
        state.activeTool = .select
        state.isDetailPanelExpanded = true
        moveStartPoint = point
        state.beginMoveSelected()
        isMoving = true
        didMoveSelected = false
    }

    private func activateEditingTool(for annotation: Annotation) {
        guard let state else { return }

        state.cancelDraw()
        state.selectedAnnotationID = annotation.id
        if let tool = annotation.editingTool, tool.isEnabled {
            state.activeTool = tool
            state.isDetailPanelExpanded = true
        }
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
        guard bounds.contains(viewPoint) else { return }

        let documentPoint = CanvasGeometry.documentPoint(fromImagePixel: viewPoint, effectiveCrop: effectiveCrop)

        if scrollView?.isSpaceHeld != true, draggableAnnotation(at: documentPoint) != nil {
            NSCursor.openHand.set()
        } else {
            baseCursor.set()
        }
    }

    private var baseCursor: NSCursor {
        if scrollView?.isSpaceHeld == true {
            return .openHand
        }

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

private extension Annotation {
    var editingTool: EditorTool? {
        switch kind {
        case .arrow:
            return .arrow
        case .rect:
            return .rectangle
        case .text:
            return .text
        case .blur:
            return .blur
        }
    }

    var isDraggableShape: Bool {
        switch kind {
        case .arrow, .rect:
            return true
        case .text, .blur:
            return false
        }
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
