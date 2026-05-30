import AppKit

@MainActor
final class CanvasTextEditor: NSObject, NSTextFieldDelegate {

    private weak var container: NSView?
    private weak var state: EditorState?
    private var field: NSTextField?
    private var editingID: UUID?
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

    func beginEditing(_ annotation: Annotation, effectiveCrop: CGRect) {
        guard case let .text(origin, string, fontSize, color) = annotation.kind,
              let container else { return }
        finishEditing()

        let textField = NSTextField(frame: .zero)
        textField.isBordered = false
        textField.drawsBackground = true
        textField.backgroundColor = NSColor.white.withAlphaComponent(0.08)
        textField.focusRingType = .none
        textField.stringValue = string
        textField.delegate = self
        textField.usesSingleLineMode = true
        textField.lineBreakMode = .byClipping

        container.addSubview(textField)
        field = textField
        editingID = annotation.id
        syncTextField(textField, origin: origin, string: string, fontSize: fontSize, color: color, effectiveCrop: effectiveCrop)
        container.window?.makeFirstResponder(textField)
    }

    func syncEditingField(with document: EditorDocument, effectiveCrop: CGRect) {
        guard let textField = field, let id = editingID else { return }
        guard let annotation = document.annotations.first(where: { $0.id == id }),
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
            effectiveCrop: effectiveCrop
        )
    }

    func finishEditing() {
        guard let textField = field, let id = editingID, let state else { return }
        let text = textField.stringValue
        textField.removeFromSuperview()
        field = nil
        editingID = nil

        guard let index = state.document.annotations.firstIndex(where: { $0.id == id }),
              case let .text(origin, oldString, fontSize, color) = state.document.annotations[index].kind else {
            return
        }

        state.selectedAnnotationID = id
        if text.isEmpty {
            state.deleteSelectedAnnotation()
        } else if text != oldString {
            state.updateSelectedKind(.text(origin: origin, string: text, fontSize: fontSize, color: color))
        }
    }

    func controlTextDidEndEditing(_ obj: Notification) {
        finishEditing()
    }

    private func syncTextField(
        _ textField: NSTextField,
        origin: CGPoint,
        string: String,
        fontSize: CGFloat,
        color: CGColor,
        effectiveCrop: CGRect
    ) {
        let imageOrigin = CanvasGeometry.imagePixel(fromDocumentPoint: origin, effectiveCrop: effectiveCrop)
        let box = AnnotationGeometry.textFrame(origin: origin, string: string, fontSize: fontSize)
        textField.frame = CGRect(
            x: imageFrameOrigin.x + imageOrigin.x,
            y: imageFrameOrigin.y + imageOrigin.y,
            width: max(box.width, fontSize * 4),
            height: box.height
        )
        textField.font = NSFont(name: "Helvetica", size: fontSize) ?? NSFont.systemFont(ofSize: fontSize)
        textField.textColor = NSColor(cgColor: color) ?? .red
    }

    private func cancelEditing() {
        field?.removeFromSuperview()
        field = nil
        editingID = nil
    }
}
