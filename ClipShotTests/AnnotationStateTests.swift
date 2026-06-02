import AppKit
import XCTest
@testable import ClipShot

@MainActor
final class AnnotationStateTests: XCTestCase {

    private func makeState() -> EditorState {
        EditorState(
            document: EditorDocument(
                screenshot: TestImage.solid(.red, size: CGSize(width: 100, height: 100)),
                viewport: CGSize(width: 100, height: 100),
                pageTitle: "t",
                pageURL: "u",
                baseSelection: CGRect(x: 10, y: 10, width: 40, height: 40)
            )
        )
    }

    func test_drawArrow_commitPushesAnnotationAndSelects() {
        let state = makeState()
        state.activeTool = .arrow

        state.beginDraw(at: CGPoint(x: 5, y: 5))
        state.updateDraw(to: CGPoint(x: 30, y: 20), shiftSnap: false)
        XCTAssertNotNil(state.inProgressAnnotation)
        let committed = state.commitDraw()

        XCTAssertNotNil(committed)
        XCTAssertNil(state.inProgressAnnotation)
        XCTAssertEqual(state.document.annotations.count, 1)
        XCTAssertEqual(state.selectedAnnotationID, committed?.id)
        XCTAssertEqual(state.activeTool, .select)
        XCTAssertTrue(state.undoStack.canUndo)
    }

    func test_drawArrow_degenerateDiscarded() {
        let state = makeState()
        state.activeTool = .arrow

        state.beginDraw(at: CGPoint(x: 5, y: 5))
        state.updateDraw(to: CGPoint(x: 6, y: 6), shiftSnap: false)

        XCTAssertNil(state.commitDraw())
        XCTAssertEqual(state.document.annotations.count, 0)
    }

    func test_drawRect_clampsToDocumentBounds() {
        let state = makeState()
        state.activeTool = .rectangle

        state.beginDraw(at: CGPoint(x: 5, y: 5))
        state.updateDraw(to: CGPoint(x: 999, y: 999), shiftSnap: false)

        if case let .rect(frame, _, _, _, _) = state.inProgressAnnotation?.kind {
            XCTAssertLessThanOrEqual(frame.maxX, state.documentBounds.maxX + 0.5)
            XCTAssertLessThanOrEqual(frame.maxY, state.documentBounds.maxY + 0.5)
        } else {
            XCTFail("expected rect")
        }
    }

    func test_selectAndDelete_removesAndUndoRestores() {
        let state = makeState()
        state.activeTool = .arrow
        state.beginDraw(at: CGPoint(x: 5, y: 5))
        state.updateDraw(to: CGPoint(x: 30, y: 30), shiftSnap: false)
        let annotation = state.commitDraw()!

        state.selectAnnotation(at: CGPoint(x: 17, y: 17))
        XCTAssertEqual(state.selectedAnnotationID, annotation.id)
        state.deleteSelectedAnnotation()
        XCTAssertEqual(state.document.annotations.count, 0)
        state.performUndo()
        XCTAssertEqual(state.document.annotations.count, 1)
    }

    func test_move_commitsSingleUndoEntry() {
        let state = makeState()
        state.activeTool = .arrow
        state.beginDraw(at: CGPoint(x: 5, y: 5))
        state.updateDraw(to: CGPoint(x: 25, y: 25), shiftSnap: false)
        _ = state.commitDraw()
        let undoBefore = state.undoStack.undoCount

        state.beginMoveSelected()
        state.moveSelected(by: CGSize(width: 3, height: 3))
        state.moveSelected(by: CGSize(width: 6, height: 6))
        state.commitMoveSelected()

        XCTAssertEqual(state.undoStack.undoCount, undoBefore + 1)
        state.performUndo()
        if case let .arrow(from, _, _, _) = state.document.annotations[0].kind {
            XCTAssertEqual(from, CGPoint(x: 5, y: 5))
        } else {
            XCTFail("expected arrow")
        }
    }

    func test_selectToolPanelVisible_onlyWithSelection() {
        let state = makeState()
        state.activeTool = .select
        XCTAssertFalse(state.isInspectorVisible)

        state.activeTool = .arrow
        state.beginDraw(at: CGPoint(x: 5, y: 5))
        state.updateDraw(to: CGPoint(x: 25, y: 25), shiftSnap: false)
        _ = state.commitDraw()
        state.activeTool = .select

        XCTAssertTrue(state.isInspectorVisible)
    }

    func test_undoAddClearsStaleSelection() {
        let state = makeState()
        state.activeTool = .arrow
        state.beginDraw(at: CGPoint(x: 5, y: 5))
        state.updateDraw(to: CGPoint(x: 25, y: 25), shiftSnap: false)
        _ = state.commitDraw()

        state.performUndo()

        XCTAssertNil(state.selectedAnnotationID)
        // commitDraw pinned the Select inspector; undoing the only annotation leaves the
        // component list open (now empty), not a hidden inspector.
        XCTAssertEqual(state.inspectorRoute, .componentList)
    }
}

@MainActor
final class CanvasTextEditorTests: XCTestCase {

    func test_syncEditingField_updatesActiveTextFieldFontAndFrame() throws {
        let container = NSView(frame: CGRect(x: 0, y: 0, width: 300, height: 200))
        let editor = CanvasTextEditor(container: container)
        let annotation = Annotation(
            kind: .text(
                origin: CGPoint(x: 5, y: 5),
                string: "Text",
                fontSize: 12,
                color: CGColor(gray: 0, alpha: 1)
            )
        )
        var document = EditorDocument(
            screenshot: TestImage.solid(.red, size: CGSize(width: 100, height: 100)),
            viewport: CGSize(width: 100, height: 100),
            pageTitle: "t",
            pageURL: "u",
            baseSelection: CGRect(x: 0, y: 0, width: 80, height: 80),
            annotations: [annotation]
        )
        let state = EditorState(document: document)
        editor.attach(state: state)
        editor.imageFrameOrigin = CGPoint(x: 10, y: 20)
        editor.beginEditing(annotation, effectiveCrop: document.effectiveCrop)

        let textField = try XCTUnwrap(container.subviews.compactMap { $0 as? NSTextField }.first)
        XCTAssertFalse(textField.drawsBackground)
        let initialFrame = textField.frame
        textField.stringValue = "Current typed text"
        document.annotations[0].kind = .text(
            origin: CGPoint(x: 5, y: 5),
            string: "Text",
            fontSize: 36,
            color: CGColor(gray: 0, alpha: 1)
        )

        editor.syncEditingField(with: document, effectiveCrop: document.effectiveCrop)

        XCTAssertEqual(textField.stringValue, "Current typed text")
        XCTAssertEqual(textField.font?.pointSize ?? 0, 36, accuracy: 0.1)
        XCTAssertGreaterThan(textField.frame.width, initialFrame.width)
        XCTAssertGreaterThan(textField.frame.height, initialFrame.height)
    }

    func test_smallEditingTextBorderClickFallsThroughToCanvasInteraction() throws {
        let container = CanvasDocumentView(frame: CGRect(x: 0, y: 0, width: 120, height: 80))
        let annotation = Annotation(
            kind: .text(
                origin: CGPoint(x: 10, y: 10),
                string: "i",
                fontSize: 8,
                color: CGColor(gray: 0, alpha: 1)
            )
        )
        let document = EditorDocument(
            screenshot: TestImage.solid(.red, size: CGSize(width: 100, height: 100)),
            viewport: CGSize(width: 100, height: 100),
            pageTitle: "t",
            pageURL: "u",
            baseSelection: CGRect(x: 0, y: 0, width: 80, height: 80),
            annotations: [annotation]
        )
        let state = EditorState(document: document, openingPanel: .components)
        let interactionView = CanvasInteractionView(frame: container.bounds)
        interactionView.state = state
        interactionView.effectiveCrop = document.effectiveCrop
        container.addSubview(interactionView)

        let editor = CanvasTextEditor(container: container)
        editor.attach(state: state)
        editor.onEditingPreviewChanged = { annotation in
            interactionView.editingTextAnnotation = annotation
        }
        editor.beginEditing(annotation, effectiveCrop: document.effectiveCrop)

        let textField = try XCTUnwrap(container.subviews.compactMap { $0 as? NSTextField }.first)
        let textFrame = AnnotationGeometry.boundingBox(annotation.kind)
        let borderPoint = CGPoint(x: textFrame.maxX + 9, y: textFrame.midY)
        let textFieldPoint = textField.convert(borderPoint, from: container)
        let interactionPoint = interactionView.convert(borderPoint, from: container)

        XCTAssertTrue(textField.frame.contains(borderPoint))
        XCTAssertNil(textField.hitTest(textFieldPoint))
        XCTAssertIdentical(interactionView.hitTest(interactionPoint), interactionView)
    }

    func test_controlTextDidChange_emitsPreviewForCurrentTypedText() throws {
        let container = NSView(frame: CGRect(x: 0, y: 0, width: 300, height: 200))
        let editor = CanvasTextEditor(container: container)
        let annotation = Annotation(
            kind: .text(
                origin: CGPoint(x: 5, y: 5),
                string: "Text",
                fontSize: 12,
                color: CGColor(gray: 0, alpha: 1)
            )
        )
        let document = EditorDocument(
            screenshot: TestImage.solid(.red, size: CGSize(width: 100, height: 100)),
            viewport: CGSize(width: 100, height: 100),
            pageTitle: "t",
            pageURL: "u",
            baseSelection: CGRect(x: 0, y: 0, width: 80, height: 80),
            annotations: [annotation]
        )
        let state = EditorState(document: document)
        var latestPreview: Annotation?
        var didClearPreview = false
        editor.onEditingPreviewChanged = { preview in
            latestPreview = preview
            didClearPreview = preview == nil
        }
        editor.attach(state: state)
        editor.beginEditing(annotation, effectiveCrop: document.effectiveCrop)

        let textField = try XCTUnwrap(container.subviews.compactMap { $0 as? NSTextField }.first)
        let initialFrame = textField.frame
        textField.stringValue = "Current typed text"
        editor.controlTextDidChange(Notification(name: NSControl.textDidChangeNotification, object: textField))

        let preview = try XCTUnwrap(latestPreview)
        if case let .text(_, string, _, _) = preview.kind {
            XCTAssertEqual(string, "Current typed text")
        } else {
            XCTFail("expected text preview")
        }
        XCTAssertGreaterThan(textField.frame.width, initialFrame.width)

        editor.finishEditing()
        XCTAssertTrue(didClearPreview)
    }

    func test_finishEditingBlankNewTextDraftNeverCreatesAnnotation() throws {
        let container = NSView(frame: CGRect(x: 0, y: 0, width: 300, height: 200))
        let editor = CanvasTextEditor(container: container)
        let document = EditorDocument(
            screenshot: TestImage.solid(.red, size: CGSize(width: 100, height: 100)),
            viewport: CGSize(width: 100, height: 100),
            pageTitle: "t",
            pageURL: "u",
            baseSelection: CGRect(x: 0, y: 0, width: 80, height: 80)
        )
        let state = EditorState(document: document)
        state.activeTool = .text
        let annotation = try XCTUnwrap(state.beginTextDraft(at: CGPoint(x: 5, y: 5)))
        editor.attach(state: state)
        editor.beginEditing(annotation, effectiveCrop: state.document.effectiveCrop)

        let textField = try XCTUnwrap(container.subviews.compactMap { $0 as? NSTextField }.first)
        XCTAssertEqual(state.document.annotations.count, 0)
        XCTAssertEqual(state.inspectorRoute, .drawDefaults(.text))
        XCTAssertNotNil(state.inProgressAnnotation)

        textField.stringValue = "   "
        editor.finishEditing()

        XCTAssertEqual(state.document.annotations.count, 0)
        XCTAssertNil(state.selectedAnnotationID)
        XCTAssertNil(state.inProgressAnnotation)
        XCTAssertEqual(state.undoStack.undoCount, 0)
        state.performUndo()
        XCTAssertEqual(state.document.annotations.count, 0)
    }

    func test_finishEditingNonBlankNewTextDraftCreatesAnnotationAndSelectsIt() throws {
        let container = NSView(frame: CGRect(x: 0, y: 0, width: 300, height: 200))
        let editor = CanvasTextEditor(container: container)
        let document = EditorDocument(
            screenshot: TestImage.solid(.red, size: CGSize(width: 100, height: 100)),
            viewport: CGSize(width: 100, height: 100),
            pageTitle: "t",
            pageURL: "u",
            baseSelection: CGRect(x: 0, y: 0, width: 80, height: 80)
        )
        let state = EditorState(document: document)
        state.activeTool = .text
        let annotation = try XCTUnwrap(state.beginTextDraft(at: CGPoint(x: 5, y: 5)))
        editor.attach(state: state)
        editor.beginEditing(annotation, effectiveCrop: state.document.effectiveCrop)

        let textField = try XCTUnwrap(container.subviews.compactMap { $0 as? NSTextField }.first)
        XCTAssertEqual(state.document.annotations.count, 0)

        textField.stringValue = "Hello"
        editor.finishEditing()

        XCTAssertEqual(state.document.annotations.count, 1)
        XCTAssertEqual(state.selectedAnnotationID, annotation.id)
        XCTAssertEqual(state.activeTool, .select)
        XCTAssertNil(state.inProgressAnnotation)
        XCTAssertEqual(state.undoStack.undoCount, 1)
        XCTAssertEqual(state.inspectorRoute, .annotation)
        if case let .text(_, string, _, _) = state.document.annotations[0].kind {
            XCTAssertEqual(string, "Hello")
        } else {
            XCTFail("expected text")
        }
    }

    func test_finishEditingBlankExistingTextDeletesWithUndo() throws {
        let container = NSView(frame: CGRect(x: 0, y: 0, width: 300, height: 200))
        let editor = CanvasTextEditor(container: container)
        let annotation = Annotation(
            kind: .text(
                origin: CGPoint(x: 5, y: 5),
                string: "Text",
                fontSize: 12,
                color: CGColor(gray: 0, alpha: 1)
            )
        )
        let document = EditorDocument(
            screenshot: TestImage.solid(.red, size: CGSize(width: 100, height: 100)),
            viewport: CGSize(width: 100, height: 100),
            pageTitle: "t",
            pageURL: "u",
            baseSelection: CGRect(x: 0, y: 0, width: 80, height: 80),
            annotations: [annotation]
        )
        let state = EditorState(document: document)
        editor.attach(state: state)
        editor.beginEditing(annotation, effectiveCrop: document.effectiveCrop)

        let textField = try XCTUnwrap(container.subviews.compactMap { $0 as? NSTextField }.first)
        textField.stringValue = ""
        editor.finishEditing()

        XCTAssertEqual(state.document.annotations.count, 0)
        XCTAssertNil(state.selectedAnnotationID)
        XCTAssertEqual(state.undoStack.undoCount, 1)

        state.performUndo()
        XCTAssertEqual(state.document.annotations.count, 1)
        if case let .text(_, string, _, _) = state.document.annotations[0].kind {
            XCTAssertEqual(string, "Text")
        } else {
            XCTFail("expected restored text")
        }
    }

    func test_arrowCommandsAreNotHandledWhileEditingText() throws {
        let container = NSView(frame: CGRect(x: 0, y: 0, width: 300, height: 200))
        let editor = CanvasTextEditor(container: container)
        let annotation = Annotation(
            kind: .text(
                origin: CGPoint(x: 10, y: 10),
                string: "Text",
                fontSize: 12,
                color: CGColor(gray: 0, alpha: 1)
            )
        )
        let document = EditorDocument(
            screenshot: TestImage.solid(.red, size: CGSize(width: 100, height: 100)),
            viewport: CGSize(width: 100, height: 100),
            pageTitle: "t",
            pageURL: "u",
            baseSelection: CGRect(x: 0, y: 0, width: 80, height: 80),
            annotations: [annotation]
        )
        let state = EditorState(document: document)
        state.selectedAnnotationID = annotation.id
        editor.attach(state: state)
        editor.beginEditing(annotation, effectiveCrop: document.effectiveCrop)

        let textField = try XCTUnwrap(container.subviews.compactMap { $0 as? NSTextField }.first)
        textField.stringValue = "Typed"
        let textView = NSTextView()
        textView.string = "Typed"
        textView.setSelectedRange(NSRange(location: 0, length: 0))

        XCTAssertFalse(
            editor.control(
                textField,
                textView: textView,
                doCommandBy: #selector(NSResponder.moveUp(_:))
            )
        )
        XCTAssertFalse(
            editor.control(
                textField,
                textView: textView,
                doCommandBy: #selector(NSResponder.moveLeft(_:))
            )
        )
        textView.setSelectedRange(NSRange(location: 5, length: 0))
        XCTAssertFalse(
            editor.control(
                textField,
                textView: textView,
                doCommandBy: #selector(NSResponder.moveRight(_:))
            )
        )
        XCTAssertFalse(
            editor.control(
                textField,
                textView: textView,
                doCommandBy: #selector(NSResponder.moveDown(_:))
            )
        )

        if case let .text(origin, documentString, _, _) = state.document.annotations[0].kind {
            XCTAssertEqual(origin, CGPoint(x: 10, y: 10))
            XCTAssertEqual(documentString, "Text")
        } else {
            XCTFail("expected text")
        }
        XCTAssertEqual(state.undoStack.undoCount, 0)
    }
}

@MainActor
final class CanvasInteractionViewTests: XCTestCase {
    private nonisolated static let interactionViewSize = CGSize(width: 160, height: 80)

    func test_singleClickInsideTextSelectsWithoutEditing() throws {
        let (annotation, state, view) = makeTextInteraction(initialTool: .select)
        var editedAnnotation: Annotation?
        view.onEditText = { editedAnnotation = $0 }

        view.mouseDown(with: try makeMouseDown(at: CGPoint(x: 20, y: 18)))
        view.mouseUp(with: try makeMouseEvent(type: .leftMouseUp, at: CGPoint(x: 20, y: 18)))

        XCTAssertNil(editedAnnotation)
        XCTAssertEqual(state.selectedAnnotationID, annotation.id)
        XCTAssertEqual(state.activeTool, .select)
        XCTAssertEqual(state.document.annotations.count, 1)
    }

    func test_drawArrowViaCanvasReturnsToSelectTool() throws {
        let (state, view) = makeEmptyInteraction(initialTool: .arrow)

        view.mouseDown(with: try makeMouseDown(at: CGPoint(x: 10, y: 10)))
        view.mouseDragged(with: try makeMouseEvent(type: .leftMouseDragged, at: CGPoint(x: 45, y: 35)))
        view.mouseUp(with: try makeMouseEvent(type: .leftMouseUp, at: CGPoint(x: 45, y: 35)))

        XCTAssertEqual(state.document.annotations.count, 1)
        XCTAssertEqual(state.selectedAnnotationID, state.document.annotations.first?.id)
        XCTAssertEqual(state.activeTool, .select)
        XCTAssertEqual(state.inspectorRoute, .annotation)
        XCTAssertNil(state.inProgressAnnotation)
    }

    func test_textToolClickStartsDraftWithoutComponentListEntry() throws {
        let (state, view) = makeEmptyInteraction(initialTool: .text)
        var editedAnnotation: Annotation?
        view.onEditText = { editedAnnotation = $0 }

        view.mouseDown(with: try makeMouseDown(at: CGPoint(x: 20, y: 20)))

        let draft = try XCTUnwrap(editedAnnotation)
        XCTAssertEqual(state.document.annotations.count, 0)
        XCTAssertEqual(state.inProgressAnnotation?.id, draft.id)
        XCTAssertNil(state.selectedAnnotationID)
        XCTAssertEqual(state.activeTool, .text)
        XCTAssertEqual(state.inspectorRoute, .drawDefaults(.text))
        XCTAssertEqual(state.undoStack.undoCount, 0)
    }

    func test_switchingToolCommitsActiveNonBlankTextDraftAndSelectsIt() throws {
        let document = EditorDocument(
            screenshot: TestImage.solid(.red, size: CGSize(width: 100, height: 100)),
            viewport: CGSize(width: 100, height: 100),
            pageTitle: "t",
            pageURL: "u",
            baseSelection: CGRect(x: 0, y: 0, width: 80, height: 80)
        )
        let state = EditorState(document: document)
        let coordinator = CanvasCoordinator()
        coordinator.update(state: state)

        state.selectCursorTool(.text)
        let draft = try XCTUnwrap(state.beginTextDraft(at: CGPoint(x: 20, y: 20)))
        coordinator.update(state: state)
        coordinator.textEditor.beginEditing(draft, effectiveCrop: document.effectiveCrop)
        let textField = try XCTUnwrap(
            (coordinator.scrollView.documentView as? NSView)?
                .subviews
                .compactMap { $0 as? NSTextField }
                .first
        )
        textField.stringValue = "Hello"

        state.selectCursorTool(.arrow)
        coordinator.update(state: state)

        XCTAssertEqual(state.document.annotations.count, 1)
        XCTAssertEqual(state.selectedAnnotationID, draft.id)
        XCTAssertEqual(state.activeTool, .select)
        XCTAssertEqual(state.inspectorRoute, .annotation)
        XCTAssertNil(state.inProgressAnnotation)
        XCTAssertTrue(
            ((coordinator.scrollView.documentView as? NSView)?
                .subviews
                .compactMap { $0 as? NSTextField } ?? [])
                .isEmpty
        )
    }

    func test_switchingToolDiscardsActiveBlankTextDraftAndKeepsRequestedTool() throws {
        let document = EditorDocument(
            screenshot: TestImage.solid(.red, size: CGSize(width: 100, height: 100)),
            viewport: CGSize(width: 100, height: 100),
            pageTitle: "t",
            pageURL: "u",
            baseSelection: CGRect(x: 0, y: 0, width: 80, height: 80)
        )
        let state = EditorState(document: document)
        let coordinator = CanvasCoordinator()
        coordinator.update(state: state)

        state.selectCursorTool(.text)
        let draft = try XCTUnwrap(state.beginTextDraft(at: CGPoint(x: 20, y: 20)))
        coordinator.update(state: state)
        coordinator.textEditor.beginEditing(draft, effectiveCrop: document.effectiveCrop)
        let textField = try XCTUnwrap(
            (coordinator.scrollView.documentView as? NSView)?
                .subviews
                .compactMap { $0 as? NSTextField }
                .first
        )
        textField.stringValue = "   "

        state.selectCursorTool(.rectangle)
        coordinator.update(state: state)

        XCTAssertEqual(state.document.annotations.count, 0)
        XCTAssertNil(state.selectedAnnotationID)
        XCTAssertEqual(state.activeTool, .rectangle)
        XCTAssertEqual(state.inspectorRoute, .drawDefaults(.rectangle))
        XCTAssertNil(state.inProgressAnnotation)
        XCTAssertTrue(
            ((coordinator.scrollView.documentView as? NSView)?
                .subviews
                .compactMap { $0 as? NSTextField } ?? [])
                .isEmpty
        )
    }

    func test_returnCommittedSmallTextSwitchesToSelectAndDragsFromBody() throws {
        let document = EditorDocument(
            screenshot: TestImage.solid(.red, size: CGSize(width: 100, height: 100)),
            viewport: CGSize(width: 100, height: 100),
            pageTitle: "t",
            pageURL: "u",
            baseSelection: CGRect(x: 0, y: 0, width: 80, height: 80)
        )
        let state = EditorState(document: document)
        state.selectCursorTool(.text)
        let container = CanvasDocumentView(frame: CGRect(origin: .zero, size: Self.interactionViewSize))
        let view = CanvasInteractionView(frame: container.bounds)
        view.state = state
        view.effectiveCrop = document.effectiveCrop
        container.addSubview(view)
        let editor = CanvasTextEditor(container: container)
        editor.attach(state: state)
        view.onEditText = { annotation in
            editor.beginEditing(annotation, effectiveCrop: document.effectiveCrop)
        }
        view.onCommitActiveText = {
            guard editor.isEditing else { return false }
            editor.finishEditing()
            return true
        }

        view.mouseDown(with: try makeMouseDown(at: CGPoint(x: 20, y: 20)))
        let textField = try XCTUnwrap(container.subviews.compactMap { $0 as? NSTextField }.first)
        textField.stringValue = "i"
        let textView = NSTextView()
        textView.string = "i"

        XCTAssertTrue(
            editor.control(
                textField,
                textView: textView,
                doCommandBy: #selector(NSResponder.insertNewline(_:))
            )
        )

        XCTAssertTrue(container.subviews.compactMap { $0 as? NSTextField }.isEmpty)
        XCTAssertEqual(state.activeTool, .select)
        XCTAssertEqual(state.selectedAnnotationID, state.document.annotations.first?.id)
        XCTAssertNil(state.inProgressAnnotation)
        XCTAssertEqual(state.document.annotations.count, 1)

        let start = CGPoint(x: 24, y: 32)
        XCTAssertIdentical(view.hitTest(start), view)
        view.mouseDown(with: try makeMouseDown(at: start))
        view.mouseDragged(with: try makeMouseEvent(type: .leftMouseDragged, at: CGPoint(x: 34, y: 40)))
        view.mouseUp(with: try makeMouseEvent(type: .leftMouseUp, at: CGPoint(x: 34, y: 40)))

        XCTAssertEqual(state.document.annotations.count, 1)
        XCTAssertNil(state.inProgressAnnotation)
        XCTAssertEqual(state.activeTool, .select)
        if case let .text(origin, string, _, _) = state.document.annotations[0].kind {
            XCTAssertEqual(origin, CGPoint(x: 30, y: 28))
            XCTAssertEqual(string, "i")
        } else {
            XCTFail("expected text")
        }
    }

    func test_textBorderClickAfterCommitSwitchesToSelectAndMovesText() throws {
        let document = EditorDocument(
            screenshot: TestImage.solid(.red, size: CGSize(width: 100, height: 100)),
            viewport: CGSize(width: 100, height: 100),
            pageTitle: "t",
            pageURL: "u",
            baseSelection: CGRect(x: 0, y: 0, width: 80, height: 80)
        )
        let state = EditorState(document: document)
        state.selectCursorTool(.text)
        let container = CanvasDocumentView(frame: CGRect(origin: .zero, size: Self.interactionViewSize))
        let view = CanvasInteractionView(frame: container.bounds)
        view.state = state
        view.effectiveCrop = document.effectiveCrop
        container.addSubview(view)
        let editor = CanvasTextEditor(container: container)
        editor.attach(state: state)
        view.onEditText = { annotation in
            editor.beginEditing(annotation, effectiveCrop: document.effectiveCrop)
        }

        view.mouseDown(with: try makeMouseDown(at: CGPoint(x: 20, y: 20)))
        let textField = try XCTUnwrap(container.subviews.compactMap { $0 as? NSTextField }.first)
        textField.stringValue = "Hi"
        let textView = NSTextView()
        textView.string = "Hi"
        _ = editor.control(
            textField,
            textView: textView,
            doCommandBy: #selector(NSResponder.insertNewline(_:))
        )

        let annotation = try XCTUnwrap(state.document.annotations.first)
        let start = nearRightTextBorderEdgePoint(for: annotation)
        var hoveredIDs: [UUID?] = []
        view.onHoverAnnotationChanged = { hoveredIDs.append($0) }
        view.mouseMoved(with: try makeMouseEvent(type: .mouseMoved, at: start))

        XCTAssertEqual(hoveredIDs.last ?? nil, annotation.id)
        XCTAssertIdentical(view.hitTest(start), view)
        view.mouseDown(with: try makeMouseDown(at: start))
        view.mouseDragged(
            with: try makeMouseEvent(
                type: .leftMouseDragged,
                at: CGPoint(x: start.x + 10, y: start.y + 8)
            )
        )
        view.mouseUp(
            with: try makeMouseEvent(
                type: .leftMouseUp,
                at: CGPoint(x: start.x + 10, y: start.y + 8)
            )
        )

        if case let .text(origin, string, _, _) = state.document.annotations[0].kind {
            XCTAssertEqual(origin, CGPoint(x: 30, y: 28))
            XCTAssertEqual(string, "Hi")
        } else {
            XCTFail("expected text")
        }
        XCTAssertEqual(state.activeTool, .select)
        XCTAssertEqual(state.selectedAnnotationID, annotation.id)
        XCTAssertEqual(state.undoStack.undoCount, 2)
    }

    func test_singleClickInsideTextBodyWithTextToolStartsNewTextDraft() throws {
        let (annotation, state, view) = makeTextInteraction(initialTool: .text)
        var editedAnnotation: Annotation?
        view.onEditText = { editedAnnotation = $0 }

        view.mouseDown(with: try makeMouseDown(at: CGPoint(x: 20, y: 18)))
        view.mouseUp(with: try makeMouseEvent(type: .leftMouseUp, at: CGPoint(x: 20, y: 18)))

        XCTAssertNotNil(editedAnnotation)
        XCTAssertNotEqual(editedAnnotation?.id, annotation.id)
        XCTAssertEqual(state.inProgressAnnotation?.id, editedAnnotation?.id)
        XCTAssertNil(state.selectedAnnotationID)
        XCTAssertEqual(state.activeTool, .text)
        XCTAssertEqual(state.document.annotations.count, 1)
    }

    func test_smallJitterOnTextBorderWithTextToolStartsDraftWithoutMovingExistingText() throws {
        let (annotation, state, view) = makeTextInteraction(initialTool: .text)
        var editedAnnotation: Annotation?
        view.onEditText = { editedAnnotation = $0 }

        view.mouseDown(with: try makeMouseDown(at: CGPoint(x: 7, y: 18)))
        view.mouseDragged(with: try makeMouseEvent(type: .leftMouseDragged, at: CGPoint(x: 8, y: 19)))
        view.mouseUp(with: try makeMouseEvent(type: .leftMouseUp, at: CGPoint(x: 8, y: 19)))

        XCTAssertNotNil(editedAnnotation)
        XCTAssertNotEqual(editedAnnotation?.id, annotation.id)
        XCTAssertNil(state.selectedAnnotationID)
        XCTAssertEqual(state.activeTool, .text)
        XCTAssertEqual(state.inProgressAnnotation?.id, editedAnnotation?.id)
        XCTAssertEqual(state.undoStack.undoCount, 0)

        if case let .text(origin, _, _, _) = state.document.annotations[0].kind {
            XCTAssertEqual(origin, CGPoint(x: 10, y: 10))
        } else {
            XCTFail("expected text")
        }
    }

    func test_doubleClickInsideTextSwitchesToTextToolAndStartsEditing() throws {
        let (annotation, state, view) = makeTextInteraction(initialTool: .select)
        var editedAnnotation: Annotation?
        view.onEditText = { editedAnnotation = $0 }

        view.mouseDown(with: try makeMouseDown(at: CGPoint(x: 20, y: 18), clickCount: 2))

        XCTAssertEqual(editedAnnotation?.id, annotation.id)
        XCTAssertEqual(state.selectedAnnotationID, annotation.id)
        XCTAssertEqual(state.activeTool, .text)
        XCTAssertEqual(state.inspectorRoute, .annotation)
        XCTAssertEqual(state.document.annotations.count, 1)
        XCTAssertNil(state.inProgressAnnotation)
    }

    func test_textToolDragOverTextBorderStartsNewDraftInsteadOfMovingExistingText() throws {
        let (annotation, state, view) = makeTextInteraction(initialTool: .text)
        var editedAnnotation: Annotation?
        view.onEditText = { editedAnnotation = $0 }

        view.mouseDown(with: try makeMouseDown(at: CGPoint(x: 7, y: 18)))
        view.mouseDragged(with: try makeMouseEvent(type: .leftMouseDragged, at: CGPoint(x: 17, y: 28)))
        view.mouseUp(with: try makeMouseEvent(type: .leftMouseUp, at: CGPoint(x: 17, y: 28)))

        XCTAssertNotNil(editedAnnotation)
        XCTAssertNotEqual(editedAnnotation?.id, annotation.id)
        XCTAssertNil(state.selectedAnnotationID)
        XCTAssertEqual(state.activeTool, .text)
        XCTAssertEqual(state.inProgressAnnotation?.id, editedAnnotation?.id)
        XCTAssertEqual(state.undoStack.undoCount, 0)

        if case let .text(origin, _, _, _) = state.document.annotations[0].kind {
            XCTAssertEqual(origin, CGPoint(x: 10, y: 10))
        } else {
            XCTFail("expected text")
        }
    }

    func test_dragTextBodyWithTextToolStartsDraftInsteadOfMovingExistingText() throws {
        let (annotation, state, view) = makeTextInteraction(initialTool: .text)
        var editedAnnotation: Annotation?
        view.onEditText = { editedAnnotation = $0 }

        view.mouseDown(with: try makeMouseDown(at: CGPoint(x: 20, y: 18)))
        view.mouseDragged(with: try makeMouseEvent(type: .leftMouseDragged, at: CGPoint(x: 30, y: 28)))
        view.mouseUp(with: try makeMouseEvent(type: .leftMouseUp, at: CGPoint(x: 30, y: 28)))

        XCTAssertNotNil(editedAnnotation)
        XCTAssertNotEqual(editedAnnotation?.id, annotation.id)
        XCTAssertEqual(state.inProgressAnnotation?.id, editedAnnotation?.id)
        XCTAssertNil(state.selectedAnnotationID)
        XCTAssertEqual(state.activeTool, .text)
        XCTAssertEqual(state.document.annotations.count, 1)
        XCTAssertEqual(state.undoStack.undoCount, 0)

        if case let .text(origin, _, _, _) = state.document.annotations[0].kind {
            XCTAssertEqual(origin, CGPoint(x: 10, y: 10))
        } else {
            XCTFail("expected text")
        }
    }

    func test_arrowToolDragOverExistingArrowCreatesNewArrow() throws {
        let (annotation, state, view) = makeArrowInteraction(initialTool: .arrow)

        view.mouseDown(with: try makeMouseDown(at: CGPoint(x: 20, y: 20)))
        view.mouseDragged(with: try makeMouseEvent(type: .leftMouseDragged, at: CGPoint(x: 30, y: 30)))
        view.mouseUp(with: try makeMouseEvent(type: .leftMouseUp, at: CGPoint(x: 30, y: 30)))

        XCTAssertNotEqual(state.selectedAnnotationID, annotation.id)
        XCTAssertEqual(state.activeTool, .select)
        XCTAssertEqual(state.document.annotations.count, 2)
        XCTAssertNil(state.inProgressAnnotation)
        XCTAssertEqual(state.undoStack.undoCount, 1)

        if case let .arrow(from, to, _, _) = state.document.annotations[0].kind {
            XCTAssertEqual(from, CGPoint(x: 10, y: 10))
            XCTAssertEqual(to, CGPoint(x: 40, y: 40))
        } else {
            XCTFail("expected existing arrow")
        }
        if case let .arrow(from, to, _, _) = state.document.annotations[1].kind {
            XCTAssertEqual(from, CGPoint(x: 20, y: 20))
            XCTAssertEqual(to, CGPoint(x: 30, y: 30))
        } else {
            XCTFail("expected new arrow")
        }
    }

    func test_doubleClickArrowSwitchesToArrowTool() throws {
        let (annotation, state, view) = makeArrowInteraction(initialTool: .select)

        view.mouseDown(with: try makeMouseDown(at: CGPoint(x: 20, y: 20), clickCount: 2))

        XCTAssertEqual(state.selectedAnnotationID, annotation.id)
        XCTAssertEqual(state.activeTool, .select)
        XCTAssertEqual(state.inspectorRoute, .annotation)
        XCTAssertEqual(state.document.annotations.count, 1)
        XCTAssertNil(state.inProgressAnnotation)
        XCTAssertEqual(state.undoStack.undoCount, 0)
    }

    func test_realDoubleClickArrowWithFirstClickJitterDoesNotMoveBeforeEditing() throws {
        let (annotation, state, view) = makeArrowInteraction(initialTool: .select)

        view.mouseDown(with: try makeMouseDown(at: CGPoint(x: 20, y: 20)))
        view.mouseDragged(with: try makeMouseEvent(type: .leftMouseDragged, at: CGPoint(x: 21, y: 21)))
        view.mouseUp(with: try makeMouseEvent(type: .leftMouseUp, at: CGPoint(x: 21, y: 21)))
        view.mouseDown(with: try makeMouseDown(at: CGPoint(x: 20, y: 20), clickCount: 2))
        view.mouseUp(with: try makeMouseEvent(type: .leftMouseUp, at: CGPoint(x: 20, y: 20), clickCount: 2))

        XCTAssertEqual(state.selectedAnnotationID, annotation.id)
        XCTAssertEqual(state.activeTool, .select)
        XCTAssertEqual(state.inspectorRoute, .annotation)
        XCTAssertEqual(state.undoStack.undoCount, 0)

        if case let .arrow(from, to, _, _) = state.document.annotations[0].kind {
            XCTAssertEqual(from, CGPoint(x: 10, y: 10))
            XCTAssertEqual(to, CGPoint(x: 40, y: 40))
        } else {
            XCTFail("expected arrow")
        }
    }

    func test_rectangleToolDragOverExistingRectangleCreatesNewRectangle() throws {
        let (annotation, state, view) = makeRectangleInteraction(initialTool: .rectangle)

        view.mouseDown(with: try makeMouseDown(at: CGPoint(x: 25, y: 20)))
        view.mouseDragged(with: try makeMouseEvent(type: .leftMouseDragged, at: CGPoint(x: 35, y: 30)))
        view.mouseUp(with: try makeMouseEvent(type: .leftMouseUp, at: CGPoint(x: 35, y: 30)))

        XCTAssertNotEqual(state.selectedAnnotationID, annotation.id)
        XCTAssertEqual(state.activeTool, .select)
        XCTAssertEqual(state.document.annotations.count, 2)
        XCTAssertNil(state.inProgressAnnotation)
        XCTAssertEqual(state.undoStack.undoCount, 1)

        if case let .rect(frame, _, _, _, _) = state.document.annotations[0].kind {
            XCTAssertEqual(frame, CGRect(x: 10, y: 10, width: 40, height: 24))
        } else {
            XCTFail("expected existing rectangle")
        }
        if case let .rect(frame, _, _, _, _) = state.document.annotations[1].kind {
            XCTAssertEqual(frame, CGRect(x: 25, y: 20, width: 10, height: 10))
        } else {
            XCTFail("expected new rectangle")
        }
    }

    func test_doubleClickRectangleSwitchesToRectangleTool() throws {
        let (annotation, state, view) = makeRectangleInteraction(initialTool: .select)

        view.mouseDown(with: try makeMouseDown(at: CGPoint(x: 25, y: 20), clickCount: 2))

        XCTAssertEqual(state.selectedAnnotationID, annotation.id)
        XCTAssertEqual(state.activeTool, .select)
        XCTAssertEqual(state.inspectorRoute, .annotation)
        XCTAssertEqual(state.document.annotations.count, 1)
        XCTAssertNil(state.inProgressAnnotation)
        XCTAssertEqual(state.undoStack.undoCount, 0)
    }

    func test_arrowToolDragOverRectangleCreatesArrowAndSwitchesToSelect() throws {
        let (annotation, state, view) = makeRectangleInteraction(initialTool: .arrow)

        view.mouseDown(with: try makeMouseDown(at: CGPoint(x: 25, y: 20)))
        view.mouseDragged(with: try makeMouseEvent(type: .leftMouseDragged, at: CGPoint(x: 35, y: 30)))
        view.mouseUp(with: try makeMouseEvent(type: .leftMouseUp, at: CGPoint(x: 35, y: 30)))

        XCTAssertNotEqual(state.selectedAnnotationID, annotation.id)
        XCTAssertEqual(state.activeTool, .select)
        XCTAssertEqual(state.document.annotations.count, 2)
        XCTAssertNil(state.inProgressAnnotation)
        XCTAssertEqual(state.undoStack.undoCount, 1)

        if case let .rect(frame, _, _, _, _) = state.document.annotations[0].kind {
            XCTAssertEqual(frame, CGRect(x: 10, y: 10, width: 40, height: 24))
        } else {
            XCTFail("expected rectangle")
        }
        if case let .arrow(from, to, _, _) = state.document.annotations[1].kind {
            XCTAssertEqual(from, CGPoint(x: 25, y: 20))
            XCTAssertEqual(to, CGPoint(x: 35, y: 30))
        } else {
            XCTFail("expected arrow")
        }
    }

    func test_rectangleToolDragOverArrowCreatesRectangleAndSwitchesToSelect() throws {
        let (annotation, state, view) = makeArrowInteraction(initialTool: .rectangle)

        view.mouseDown(with: try makeMouseDown(at: CGPoint(x: 20, y: 20)))
        view.mouseDragged(with: try makeMouseEvent(type: .leftMouseDragged, at: CGPoint(x: 35, y: 30)))
        view.mouseUp(with: try makeMouseEvent(type: .leftMouseUp, at: CGPoint(x: 35, y: 30)))

        XCTAssertNotEqual(state.selectedAnnotationID, annotation.id)
        XCTAssertEqual(state.activeTool, .select)
        XCTAssertEqual(state.document.annotations.count, 2)
        XCTAssertNil(state.inProgressAnnotation)
        XCTAssertEqual(state.undoStack.undoCount, 1)

        if case let .arrow(from, to, _, _) = state.document.annotations[0].kind {
            XCTAssertEqual(from, CGPoint(x: 10, y: 10))
            XCTAssertEqual(to, CGPoint(x: 40, y: 40))
        } else {
            XCTFail("expected arrow")
        }
        if case let .rect(frame, _, _, _, _) = state.document.annotations[1].kind {
            XCTAssertEqual(frame, CGRect(x: 20, y: 20, width: 15, height: 10))
        } else {
            XCTFail("expected rectangle")
        }
    }

    func test_textToolClickNearTextBorderStartsNewDraft() throws {
        let (annotation, state, view) = makeTextInteraction(initialTool: .text)
        var editedAnnotation: Annotation?
        view.onEditText = { editedAnnotation = $0 }
        let point = nearRightTextBorderEdgePoint(for: annotation)

        view.mouseDown(with: try makeMouseDown(at: point))
        view.mouseUp(with: try makeMouseEvent(type: .leftMouseUp, at: point))

        XCTAssertNotNil(editedAnnotation)
        XCTAssertNotEqual(editedAnnotation?.id, annotation.id)
        XCTAssertNil(state.selectedAnnotationID)
        XCTAssertEqual(state.activeTool, .text)
        XCTAssertEqual(state.document.annotations.count, 1)
        XCTAssertEqual(state.inProgressAnnotation?.id, editedAnnotation?.id)
        XCTAssertEqual(state.undoStack.undoCount, 0)
    }

    func test_textToolClickNearEditingPreviewBorderStartsNewDraft() throws {
        let (annotation, state, view) = makeTextInteraction(initialTool: .text)
        let preview = Annotation(
            id: annotation.id,
            kind: .text(
                origin: CGPoint(x: 10, y: 10),
                string: "Hello while actively editing a much wider value",
                fontSize: 20,
                color: CGColor(gray: 0, alpha: 1)
            )
        )
        view.editingTextAnnotation = preview
        var editedAnnotation: Annotation?
        view.onEditText = { editedAnnotation = $0 }
        let point = nearRightTextBorderEdgePoint(for: preview)

        view.mouseDown(with: try makeMouseDown(at: point))
        view.mouseUp(with: try makeMouseEvent(type: .leftMouseUp, at: point))

        XCTAssertNotNil(editedAnnotation)
        XCTAssertNotEqual(editedAnnotation?.id, annotation.id)
        XCTAssertNil(state.selectedAnnotationID)
        XCTAssertEqual(state.activeTool, .text)
        XCTAssertEqual(state.document.annotations.count, 1)
        XCTAssertEqual(state.inProgressAnnotation?.id, editedAnnotation?.id)
        XCTAssertEqual(state.undoStack.undoCount, 0)
    }

    func test_nonDrawingToolsCaptureAnnotationSelectionTargets() {
        let textFixture = makeTextInteraction(initialTool: .background)
        let arrowFixture = makeArrowInteraction(initialTool: .background)
        let rectFixture = makeRectangleInteraction(initialTool: .background)

        withExtendedLifetime(textFixture.state) {
            XCTAssertIdentical(textFixture.view.hitTest(CGPoint(x: 7, y: 18)), textFixture.view)
            XCTAssertIdentical(textFixture.view.hitTest(CGPoint(x: 20, y: 18)), textFixture.view)
            // The view now owns every point (pan/zoom bypass hit-testing); an empty-area
            // click is captured too, and mouseDown turns it into a deselect.
            XCTAssertIdentical(textFixture.view.hitTest(CGPoint(x: 70, y: 60)), textFixture.view)
        }
        withExtendedLifetime(arrowFixture.state) {
            XCTAssertIdentical(arrowFixture.view.hitTest(CGPoint(x: 20, y: 20)), arrowFixture.view)
        }
        withExtendedLifetime(rectFixture.state) {
            XCTAssertIdentical(rectFixture.view.hitTest(CGPoint(x: 25, y: 20)), rectFixture.view)
        }
    }

    func test_selectToolWithComponentsPanelCanSelectAnyAnnotationKind() throws {
        let cases: [(
            annotation: Annotation,
            state: EditorState,
            view: CanvasInteractionView,
            point: CGPoint
        )] = [
            {
                let fixture = makeTextInteraction(initialTool: .select)
                return (fixture.annotation, fixture.state, fixture.view, CGPoint(x: 20, y: 18))
            }(),
            {
                let fixture = makeArrowInteraction(initialTool: .select)
                return (fixture.annotation, fixture.state, fixture.view, CGPoint(x: 20, y: 20))
            }(),
            {
                let fixture = makeRectangleInteraction(initialTool: .select)
                return (fixture.annotation, fixture.state, fixture.view, CGPoint(x: 25, y: 20))
            }(),
            {
                let fixture = makeBlurInteraction(initialTool: .select)
                return (fixture.annotation, fixture.state, fixture.view, CGPoint(x: 25, y: 20))
            }()
        ]

        for testCase in cases {
            testCase.state.toggleDocumentPanel(.components)
            XCTAssertEqual(testCase.state.activeTool, .select)
            XCTAssertIdentical(testCase.view.hitTest(testCase.point), testCase.view)

            testCase.view.mouseDown(with: try makeMouseDown(at: testCase.point))
            testCase.view.mouseUp(with: try makeMouseEvent(type: .leftMouseUp, at: testCase.point))

            XCTAssertEqual(testCase.state.selectedAnnotationID, testCase.annotation.id)
            XCTAssertEqual(testCase.state.inspectorRoute, .annotation)
            XCTAssertEqual(testCase.state.undoStack.undoCount, 0)
        }
    }

    func test_selectToolCanDragAnyAnnotationKind() throws {
        let textFixture = makeTextInteraction(initialTool: .select)
        let arrowFixture = makeArrowInteraction(initialTool: .select)
        let rectFixture = makeRectangleInteraction(initialTool: .select)
        let blurFixture = makeBlurInteraction(initialTool: .select)

        try withExtendedLifetime(textFixture.state) {
            textFixture.view.mouseDown(with: try makeMouseDown(at: CGPoint(x: 20, y: 18)))
            textFixture.view.mouseDragged(with: try makeMouseEvent(type: .leftMouseDragged, at: CGPoint(x: 30, y: 28)))
            textFixture.view.mouseUp(with: try makeMouseEvent(type: .leftMouseUp, at: CGPoint(x: 30, y: 28)))

            if case let .text(origin, _, _, _) = textFixture.state.document.annotations[0].kind {
                XCTAssertEqual(origin, CGPoint(x: 20, y: 20))
            } else {
                XCTFail("expected text")
            }
        }
        try withExtendedLifetime(arrowFixture.state) {
            arrowFixture.view.mouseDown(with: try makeMouseDown(at: CGPoint(x: 20, y: 20)))
            arrowFixture.view.mouseDragged(with: try makeMouseEvent(type: .leftMouseDragged, at: CGPoint(x: 30, y: 30)))
            arrowFixture.view.mouseUp(with: try makeMouseEvent(type: .leftMouseUp, at: CGPoint(x: 30, y: 30)))

            if case let .arrow(from, to, _, _) = arrowFixture.state.document.annotations[0].kind {
                XCTAssertEqual(from, CGPoint(x: 20, y: 20))
                XCTAssertEqual(to, CGPoint(x: 50, y: 50))
            } else {
                XCTFail("expected arrow")
            }
        }
        try withExtendedLifetime(rectFixture.state) {
            rectFixture.view.mouseDown(with: try makeMouseDown(at: CGPoint(x: 25, y: 20)))
            rectFixture.view.mouseDragged(with: try makeMouseEvent(type: .leftMouseDragged, at: CGPoint(x: 35, y: 30)))
            rectFixture.view.mouseUp(with: try makeMouseEvent(type: .leftMouseUp, at: CGPoint(x: 35, y: 30)))

            if case let .rect(frame, _, _, _, _) = rectFixture.state.document.annotations[0].kind {
                XCTAssertEqual(frame, CGRect(x: 20, y: 20, width: 40, height: 24))
            } else {
                XCTFail("expected rectangle")
            }
        }
        try withExtendedLifetime(blurFixture.state) {
            blurFixture.view.mouseDown(with: try makeMouseDown(at: CGPoint(x: 25, y: 20)))
            blurFixture.view.mouseDragged(with: try makeMouseEvent(type: .leftMouseDragged, at: CGPoint(x: 35, y: 30)))
            blurFixture.view.mouseUp(with: try makeMouseEvent(type: .leftMouseUp, at: CGPoint(x: 35, y: 30)))

            if case let .blur(frame, _) = blurFixture.state.document.annotations[0].kind {
                XCTAssertEqual(frame, CGRect(x: 20, y: 20, width: 40, height: 24))
            } else {
                XCTFail("expected blur")
            }
        }
    }

    func test_selectToolArrowKeysNudgeTextArrowAndRectangleByDefaultDistance() throws {
        let textFixture = makeTextInteraction(initialTool: .select)
        let arrowFixture = makeArrowInteraction(initialTool: .select)
        let rectFixture = makeRectangleInteraction(initialTool: .select)

        try withExtendedLifetime(textFixture.state) {
            textFixture.state.selectedAnnotationID = textFixture.annotation.id
            textFixture.view.keyDown(with: try makeKeyDown(keyCode: 124))

            if case let .text(origin, _, _, _) = textFixture.state.document.annotations[0].kind {
                XCTAssertEqual(origin, CGPoint(x: 18, y: 10))
            } else {
                XCTFail("expected text")
            }
            XCTAssertEqual(textFixture.state.undoStack.undoCount, 1)
        }

        try withExtendedLifetime(arrowFixture.state) {
            arrowFixture.state.selectedAnnotationID = arrowFixture.annotation.id
            arrowFixture.view.keyDown(with: try makeKeyDown(keyCode: 125))

            if case let .arrow(from, to, _, _) = arrowFixture.state.document.annotations[0].kind {
                XCTAssertEqual(from, CGPoint(x: 10, y: 18))
                XCTAssertEqual(to, CGPoint(x: 40, y: 48))
            } else {
                XCTFail("expected arrow")
            }
            XCTAssertEqual(arrowFixture.state.undoStack.undoCount, 1)
        }

        try withExtendedLifetime(rectFixture.state) {
            rectFixture.state.selectedAnnotationID = rectFixture.annotation.id
            rectFixture.view.keyDown(with: try makeKeyDown(keyCode: 123))

            if case let .rect(frame, _, _, _, _) = rectFixture.state.document.annotations[0].kind {
                XCTAssertEqual(frame, CGRect(x: 2, y: 10, width: 40, height: 24))
            } else {
                XCTFail("expected rectangle")
            }
            XCTAssertEqual(rectFixture.state.undoStack.undoCount, 1)
        }
    }

    func test_arrowKeysDoNotNudgeOutsideSelectTool() throws {
        let textFixture = makeTextInteraction(initialTool: .text)
        let arrowFixture = makeArrowInteraction(initialTool: .arrow)
        let rectFixture = makeRectangleInteraction(initialTool: .rectangle)

        try withExtendedLifetime(textFixture.state) {
            textFixture.state.selectedAnnotationID = textFixture.annotation.id
            textFixture.view.keyDown(with: try makeKeyDown(keyCode: 124))

            if case let .text(origin, _, _, _) = textFixture.state.document.annotations[0].kind {
                XCTAssertEqual(origin, CGPoint(x: 10, y: 10))
            } else {
                XCTFail("expected text")
            }
            XCTAssertEqual(textFixture.state.undoStack.undoCount, 0)
        }

        try withExtendedLifetime(arrowFixture.state) {
            arrowFixture.state.selectedAnnotationID = arrowFixture.annotation.id
            arrowFixture.view.keyDown(with: try makeKeyDown(keyCode: 125))

            if case let .arrow(from, to, _, _) = arrowFixture.state.document.annotations[0].kind {
                XCTAssertEqual(from, CGPoint(x: 10, y: 10))
                XCTAssertEqual(to, CGPoint(x: 40, y: 40))
            } else {
                XCTFail("expected arrow")
            }
            XCTAssertEqual(arrowFixture.state.undoStack.undoCount, 0)
        }

        try withExtendedLifetime(rectFixture.state) {
            rectFixture.state.selectedAnnotationID = rectFixture.annotation.id
            rectFixture.view.keyDown(with: try makeKeyDown(keyCode: 123))

            if case let .rect(frame, _, _, _, _) = rectFixture.state.document.annotations[0].kind {
                XCTAssertEqual(frame, CGRect(x: 10, y: 10, width: 40, height: 24))
            } else {
                XCTFail("expected rectangle")
            }
            XCTAssertEqual(rectFixture.state.undoStack.undoCount, 0)
        }
    }

    private func nearRightTextBorderEdgePoint(for annotation: Annotation) -> CGPoint {
        let haloFrame = AnnotationGeometry
            .boundingBox(annotation.kind)
            .insetBy(dx: -3, dy: -3)
        return CGPoint(x: haloFrame.maxX + 9, y: haloFrame.midY)
    }

    private func makeTextInteraction(initialTool: EditorTool) -> (
        annotation: Annotation,
        state: EditorState,
        view: CanvasInteractionView
    ) {
        let annotation = Annotation(
            kind: .text(
                origin: CGPoint(x: 10, y: 10),
                string: "Hello",
                fontSize: 20,
                color: CGColor(gray: 0, alpha: 1)
            )
        )
        let document = EditorDocument(
            screenshot: TestImage.solid(.red, size: CGSize(width: 100, height: 100)),
            viewport: CGSize(width: 100, height: 100),
            pageTitle: "t",
            pageURL: "u",
            baseSelection: CGRect(x: 0, y: 0, width: 80, height: 80),
            annotations: [annotation]
        )
        let state = EditorState(document: document)
        applyInitialTool(initialTool, to: state)
        let view = CanvasInteractionView(frame: CGRect(origin: .zero, size: Self.interactionViewSize))
        view.state = state
        view.effectiveCrop = document.effectiveCrop
        return (annotation, state, view)
    }

    private func makeArrowInteraction(initialTool: EditorTool) -> (
        annotation: Annotation,
        state: EditorState,
        view: CanvasInteractionView
    ) {
        makeInteraction(
            annotation: Annotation(
                kind: .arrow(
                    from: CGPoint(x: 10, y: 10),
                    to: CGPoint(x: 40, y: 40),
                    color: CGColor(gray: 0, alpha: 1),
                    weight: 4
                )
            ),
            initialTool: initialTool
        )
    }

    private func makeRectangleInteraction(initialTool: EditorTool) -> (
        annotation: Annotation,
        state: EditorState,
        view: CanvasInteractionView
    ) {
        makeInteraction(
            annotation: Annotation(
                kind: .rect(
                    frame: CGRect(x: 10, y: 10, width: 40, height: 24),
                    stroke: CGColor(gray: 0, alpha: 1),
                    fill: nil,
                    weight: 3,
                    cornerRadius: 0
                )
            ),
            initialTool: initialTool
        )
    }

    private func makeBlurInteraction(initialTool: EditorTool) -> (
        annotation: Annotation,
        state: EditorState,
        view: CanvasInteractionView
    ) {
        makeInteraction(
            annotation: Annotation(
                kind: .blur(
                    frame: CGRect(x: 10, y: 10, width: 40, height: 24),
                    radius: 12
                )
            ),
            initialTool: initialTool
        )
    }

    private func makeInteraction(
        annotation: Annotation,
        initialTool: EditorTool
    ) -> (
        annotation: Annotation,
        state: EditorState,
        view: CanvasInteractionView
    ) {
        let document = EditorDocument(
            screenshot: TestImage.solid(.red, size: CGSize(width: 100, height: 100)),
            viewport: CGSize(width: 100, height: 100),
            pageTitle: "t",
            pageURL: "u",
            baseSelection: CGRect(x: 0, y: 0, width: 80, height: 80),
            annotations: [annotation]
        )
        let state = EditorState(document: document)
        applyInitialTool(initialTool, to: state)
        let view = CanvasInteractionView(frame: CGRect(origin: .zero, size: Self.interactionViewSize))
        view.state = state
        view.effectiveCrop = document.effectiveCrop
        return (annotation, state, view)
    }

    private func makeEmptyInteraction(initialTool: EditorTool) -> (
        state: EditorState,
        view: CanvasInteractionView
    ) {
        let document = EditorDocument(
            screenshot: TestImage.solid(.red, size: CGSize(width: 100, height: 100)),
            viewport: CGSize(width: 100, height: 100),
            pageTitle: "t",
            pageURL: "u",
            baseSelection: CGRect(x: 0, y: 0, width: 80, height: 80)
        )
        let state = EditorState(document: document)
        applyInitialTool(initialTool, to: state)
        let view = CanvasInteractionView(frame: CGRect(origin: .zero, size: Self.interactionViewSize))
        view.state = state
        view.effectiveCrop = document.effectiveCrop
        return (state, view)
    }

    /// Migrate from the old `initialTool:` init pattern: apply a tool to a freshly-created
    /// EditorState using the new cursor/panel API.
    private func applyInitialTool(_ tool: EditorTool, to state: EditorState) {
        switch tool {
        case .select:
            break // default
        case .arrow, .rectangle, .text, .blur:
            state.selectCursorTool(tool)
        case .padding:
            state.toggleDocumentPanel(.canvas)
        case .background:
            state.toggleDocumentPanel(.canvas)
        }
    }

    private func makeMouseDown(at point: CGPoint, clickCount: Int = 1) throws -> NSEvent {
        try makeMouseEvent(type: .leftMouseDown, at: point, clickCount: clickCount)
    }

    private func makeKeyDown(keyCode: UInt16) throws -> NSEvent {
        try XCTUnwrap(
            NSEvent.keyEvent(
                with: .keyDown,
                location: .zero,
                modifierFlags: [],
                timestamp: 0,
                windowNumber: 0,
                context: nil,
                characters: "",
                charactersIgnoringModifiers: "",
                isARepeat: false,
                keyCode: keyCode
            )
        )
    }

    private func makeMouseEvent(
        type: NSEvent.EventType,
        at point: CGPoint,
        clickCount: Int = 1
    ) throws -> NSEvent {
        try XCTUnwrap(
            NSEvent.mouseEvent(
                with: type,
                location: CGPoint(x: point.x, y: Self.interactionViewSize.height - point.y),
                modifierFlags: [],
                timestamp: 0,
                windowNumber: 0,
                context: nil,
                eventNumber: 0,
                clickCount: clickCount,
                pressure: 1
            )
        )
    }
}

@MainActor
final class CanvasOverlayViewTests: XCTestCase {

    func test_editingTextAnnotationDrawsOnlyExpandedSelectionHalo() throws {
        let id = UUID()
        let annotation = Annotation(
            id: id,
            kind: .text(
                origin: CGPoint(x: 5, y: 5),
                string: "A",
                fontSize: 12,
                color: CGColor(gray: 0, alpha: 1)
            )
        )
        let document = EditorDocument(
            screenshot: TestImage.solid(.red, size: CGSize(width: 100, height: 100)),
            viewport: CGSize(width: 100, height: 100),
            pageTitle: "t",
            pageURL: "u",
            baseSelection: CGRect(x: 0, y: 0, width: 80, height: 80),
            annotations: [annotation]
        )
        let overlay = CanvasOverlayView(frame: .zero)
        overlay.resizeToDocument(document)
        overlay.selectedAnnotationID = id
        overlay.editingTextAnnotation = Annotation(
            id: id,
            kind: .text(
                origin: CGPoint(x: 5, y: 5),
                string: "Current typed text",
                fontSize: 12,
                color: CGColor(gray: 0, alpha: 1)
            )
        )

        let annotationsLayer = try XCTUnwrap(overlay.layer?.sublayers?.last)
        let annotationLayer = try XCTUnwrap(annotationsLayer.sublayers?.first)
        let sublayers = annotationLayer.sublayers ?? []
        XCTAssertFalse(sublayers.contains { $0 is CATextLayer })

        let halo = try XCTUnwrap(sublayers.compactMap { $0 as? CAShapeLayer }.first)
        let originalHaloWidth = AnnotationGeometry
            .textFrame(origin: CGPoint(x: 5, y: 5), string: "A", fontSize: 12)
            .insetBy(dx: -3, dy: -3)
            .width
        XCTAssertGreaterThan(halo.path?.boundingBox.width ?? 0, originalHaloWidth)
    }
}
