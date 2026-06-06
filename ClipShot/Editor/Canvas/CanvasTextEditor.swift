import AppKit

@MainActor
final class CanvasTextEditor: NSObject, NSTextFieldDelegate {

    private weak var container: NSView?
    private weak var state: EditorState?
    private var field: NSTextField?
    private var editingID: UUID?
    private var editingBaseSelection: CGRect = .zero
    var onEditingPreviewChanged: ((Annotation?) -> Void)?
    var imageFrameOrigin: CGPoint = .zero

    init(container: NSView) {
        self.container = container
    }

    func attach(state: EditorState) {
        self.state = state
    }

    var isEditing: Bool {
        field != nil
    }

    func beginEditing(_ annotation: Annotation, baseSelection: CGRect) {
        guard case let .text(origin, string, fontSize, color) = annotation.kind,
              let container else { return }
        finishEditing()

        let textField = CanvasTextField(frame: .zero)
        textField.isBordered = false
        textField.drawsBackground = false
        textField.backgroundColor = .clear
        textField.focusRingType = .none
        textField.stringValue = string
        textField.delegate = self
        textField.usesSingleLineMode = true
        textField.lineBreakMode = .byClipping

        container.addSubview(textField)
        field = textField
        editingID = annotation.id
        editingBaseSelection = baseSelection
        syncTextField(
            textField,
            origin: origin,
            string: string,
            fontSize: fontSize,
            color: color,
            baseSelection: baseSelection
        )
        updateEditingPreview(with: annotation)
        container.window?.makeFirstResponder(textField)
    }

    func syncEditingField(with document: EditorDocument, baseSelection: CGRect) {
        guard let textField = field, let id = editingID else { return }
        editingBaseSelection = baseSelection
        guard let annotation = editingAnnotation(for: id, in: document),
              case let .text(origin, _, fontSize, color) = annotation.kind else {
            cancelEditing()
            return
        }

        syncTextField(
            textField,
            origin: origin,
            string: textField.stringValue,
            fontSize: fontSize,
            color: color,
            baseSelection: baseSelection
        )
        updateEditingPreview(with: annotation)
    }

    func finishEditing() {
        guard let textField = field, let id = editingID, let state else { return }
        let text = textField.stringValue
        textField.removeFromSuperview()
        field = nil
        editingID = nil
        onEditingPreviewChanged?(nil)

        if let index = state.document.annotations.firstIndex(where: { $0.id == id }),
           case let .text(origin, oldString, fontSize, color) = state.document.annotations[index].kind {
            let requestedTool = state.activeTool
            let requestedPanel = state.documentPanel
            state.selectedAnnotationID = id
            if text.isBlank {
                state.deleteSelectedAnnotation()
                state.activeTool = requestedTool == .text ? .select : requestedTool
                state.documentPanel = requestedTool == .text ? .components : requestedPanel
            } else if text != oldString {
                state.activeTool = .select
                state.documentPanel = .components
                state.updateSelectedKind(.text(origin: origin, string: text, fontSize: fontSize, color: color))
            } else {
                state.activeTool = .select
                state.documentPanel = .components
            }
            return
        }

        if text.isBlank {
            state.discardTextDraft(id: id)
        } else {
            state.commitTextDraft(id: id, string: text)
        }
    }

    func controlTextDidEndEditing(_ obj: Notification) {
        let id = editingID
        Task { @MainActor [weak self] in
            guard let self, self.editingID == id else { return }
            self.finishEditing()
        }
    }

    func controlTextDidChange(_ obj: Notification) {
        guard let state else { return }
        syncEditingField(with: state.document, baseSelection: editingBaseSelection)
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        switch commandSelector {
        case #selector(NSResponder.insertNewline(_:)),
             #selector(NSResponder.insertLineBreak(_:)),
             #selector(NSResponder.insertNewlineIgnoringFieldEditor(_:)):
            finishEditing()
            return true
        default:
            return false
        }
    }

    private func syncTextField(
        _ textField: NSTextField,
        origin: CGPoint,
        string: String,
        fontSize: CGFloat,
        color: CGColor,
        baseSelection: CGRect
    ) {
        let imageOrigin = CanvasGeometry.imagePixel(
            fromAnnotationPoint: origin,
            baseSelection: baseSelection
        )
        let box = AnnotationGeometry.textFrame(origin: origin, string: string, fontSize: fontSize)
        let fieldWidth = max(box.width, fontSize * 4)
        textField.frame = CGRect(
            x: imageFrameOrigin.x + imageOrigin.x,
            y: imageFrameOrigin.y + imageOrigin.y,
            width: fieldWidth,
            height: box.height
        )
        if let textField = textField as? CanvasTextField {
            textField.mouseCaptureWidth = string.isEmpty ? fieldWidth : min(fieldWidth, box.width + 2)
        }
        textField.font = NSFont(name: "Helvetica", size: fontSize) ?? NSFont.systemFont(ofSize: fontSize)
        textField.textColor = NSColor(cgColor: color) ?? .red
    }

    private func cancelEditing() {
        field?.removeFromSuperview()
        field = nil
        editingID = nil
        onEditingPreviewChanged?(nil)
    }

    private func updateEditingPreview(with annotation: Annotation) {
        guard let textField = field,
              case let .text(origin, _, fontSize, color) = annotation.kind else {
            onEditingPreviewChanged?(nil)
            return
        }

        onEditingPreviewChanged?(
            Annotation(
                id: annotation.id,
                kind: .text(
                    origin: origin,
                    string: textField.stringValue,
                    fontSize: fontSize,
                    color: color
                )
            )
        )
    }

    private func editingAnnotation(for id: UUID, in document: EditorDocument) -> Annotation? {
        if let annotation = document.annotations.first(where: { $0.id == id }) {
            return annotation
        }
        if state?.inProgressAnnotation?.id == id {
            return state?.inProgressAnnotation
        }
        return nil
    }
}

private final class CanvasTextField: NSTextField {
    var mouseCaptureWidth: CGFloat = 0

    override func hitTest(_ point: NSPoint) -> NSView? {
        guard bounds.contains(point) else { return nil }

        let captureWidth = min(bounds.width, max(1, mouseCaptureWidth))
        let captureBounds = CGRect(
            x: bounds.minX,
            y: bounds.minY,
            width: captureWidth,
            height: bounds.height
        )
        guard captureBounds.contains(point) else { return nil }

        return super.hitTest(point)
    }
}

private extension String {
    var isBlank: Bool {
        trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}
