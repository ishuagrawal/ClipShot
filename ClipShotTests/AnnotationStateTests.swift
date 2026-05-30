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
        XCTAssertFalse(state.isDetailPanelVisible)

        state.activeTool = .arrow
        state.beginDraw(at: CGPoint(x: 5, y: 5))
        state.updateDraw(to: CGPoint(x: 25, y: 25), shiftSnap: false)
        _ = state.commitDraw()
        state.activeTool = .select

        XCTAssertTrue(state.isDetailPanelVisible)
    }

    func test_undoAddClearsStaleSelection() {
        let state = makeState()
        state.activeTool = .arrow
        state.beginDraw(at: CGPoint(x: 5, y: 5))
        state.updateDraw(to: CGPoint(x: 25, y: 25), shiftSnap: false)
        _ = state.commitDraw()

        state.performUndo()

        XCTAssertNil(state.selectedAnnotationID)
        XCTAssertFalse(state.isDetailPanelVisible)
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

    func test_arrowCommandsNudgeEditingTextVertically() throws {
        let container = NSView(frame: CGRect(x: 0, y: 0, width: 300, height: 200))
        let editor = CanvasTextEditor(container: container)
        let annotation = Annotation(
            kind: .text(
                origin: CGPoint(x: 5, y: 10),
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
        var latestPreview: Annotation?
        editor.onEditingPreviewChanged = { latestPreview = $0 }
        editor.attach(state: state)
        editor.beginEditing(annotation, effectiveCrop: document.effectiveCrop)

        let textField = try XCTUnwrap(container.subviews.compactMap { $0 as? NSTextField }.first)
        let initialFrame = textField.frame
        textField.stringValue = "Typed but not finished"

        XCTAssertTrue(
            editor.control(
                textField,
                textView: NSTextView(),
                doCommandBy: #selector(NSResponder.moveUp(_:))
            )
        )

        guard case let .text(upOrigin, documentString, _, _) = state.document.annotations[0].kind else {
            return XCTFail("expected text")
        }
        XCTAssertEqual(upOrigin, CGPoint(x: 5, y: 7))
        XCTAssertEqual(documentString, "Text")
        XCTAssertLessThan(textField.frame.minY, initialFrame.minY)

        if case let .text(previewOrigin, previewString, _, _) = latestPreview?.kind {
            XCTAssertEqual(previewOrigin, CGPoint(x: 5, y: 7))
            XCTAssertEqual(previewString, "Typed but not finished")
        } else {
            XCTFail("expected text preview")
        }

        XCTAssertTrue(
            editor.control(
                textField,
                textView: NSTextView(),
                doCommandBy: #selector(NSResponder.moveDown(_:))
            )
        )

        if case let .text(downOrigin, _, _, _) = state.document.annotations[0].kind {
            XCTAssertEqual(downOrigin, CGPoint(x: 5, y: 10))
        } else {
            XCTFail("expected text")
        }
    }

    func test_leftRightCommandsNudgeEditingTextOnlyAtTextEdges() throws {
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
        var latestPreview: Annotation?
        editor.onEditingPreviewChanged = { latestPreview = $0 }
        editor.attach(state: state)
        editor.beginEditing(annotation, effectiveCrop: document.effectiveCrop)

        let textField = try XCTUnwrap(container.subviews.compactMap { $0 as? NSTextField }.first)
        textField.stringValue = "Typed"
        let textView = NSTextView()
        textView.string = "Typed"
        textView.setSelectedRange(NSRange(location: 2, length: 0))

        XCTAssertFalse(
            editor.control(
                textField,
                textView: textView,
                doCommandBy: #selector(NSResponder.moveLeft(_:))
            )
        )
        if case let .text(origin, _, _, _) = state.document.annotations[0].kind {
            XCTAssertEqual(origin, CGPoint(x: 10, y: 10))
        } else {
            XCTFail("expected text")
        }

        textView.setSelectedRange(NSRange(location: 0, length: 0))
        XCTAssertTrue(
            editor.control(
                textField,
                textView: textView,
                doCommandBy: #selector(NSResponder.moveLeft(_:))
            )
        )
        if case let .text(leftOrigin, _, _, _) = state.document.annotations[0].kind {
            XCTAssertEqual(leftOrigin, CGPoint(x: 7, y: 10))
        } else {
            XCTFail("expected text")
        }

        textView.setSelectedRange(NSRange(location: 5, length: 0))
        XCTAssertTrue(
            editor.control(
                textField,
                textView: textView,
                doCommandBy: #selector(NSResponder.moveRight(_:))
            )
        )
        if case let .text(rightOrigin, _, _, _) = state.document.annotations[0].kind {
            XCTAssertEqual(rightOrigin, CGPoint(x: 10, y: 10))
        } else {
            XCTFail("expected text")
        }

        if case let .text(previewOrigin, previewString, _, _) = latestPreview?.kind {
            XCTAssertEqual(previewOrigin, CGPoint(x: 10, y: 10))
            XCTAssertEqual(previewString, "Typed")
        } else {
            XCTFail("expected text preview")
        }
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
