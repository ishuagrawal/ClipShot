import Combine
import CoreGraphics
import Foundation

enum EditorTool: String, CaseIterable, Identifiable {
    case select
    case padding
    case background
    case arrow
    case line
    case rectangle
    case text
    case blur

    var id: String { rawValue }

    /// Tools shipped so far: Select (P0), Padding + Background (P1), Arrow/Line/Rect/Text (P2).
    var isEnabled: Bool {
        switch self {
        case .select, .padding, .background, .arrow, .line, .rectangle, .text:
            return true
        case .blur:
            return false
        }
    }

    var isDrawTool: Bool {
        switch self {
        case .arrow, .line, .rectangle, .text, .blur:
            return true
        case .select, .padding, .background:
            return false
        }
    }

    var symbolName: String {
        switch self {
        case .select:     return "cursorarrow"
        case .padding:    return "square.dashed"
        case .background: return "paintpalette"
        case .arrow:      return "arrow.up.right"
        case .line:       return "line.diagonal"
        case .rectangle:  return "rectangle"
        case .text:       return "textformat"
        case .blur:       return "drop.halffull"
        }
    }

    var displayName: String {
        switch self {
        case .select:     return "Select"
        case .padding:    return "Padding"
        case .background: return "Background"
        case .arrow:      return "Arrow"
        case .line:       return "Line"
        case .rectangle:  return "Rectangle"
        case .text:       return "Text"
        case .blur:       return "Blur / Redact"
        }
    }

}

enum DocumentPanel: Equatable {
    case none, components, canvas
}

enum InspectorRoute: Equatable {
    case hidden
    case componentList
    case canvas
    case annotation
    case drawDefaults(EditorTool)
}

@MainActor
final class EditorState: ObservableObject {
    @Published var document: EditorDocument
    /// The initial loaded state (post auto-process), captured at init. Reset reverts
    /// to this; preview shows it without committing.
    let originalDocument: EditorDocument
    /// When true the canvas shows `originalDocument` instead of `document` (compare-only).
    @Published var previewingOriginal = false
    @Published var activeTool: EditorTool = .select          // cursor mode: select/arrow/rectangle/text
    @Published var documentPanel: DocumentPanel = .none
    @Published var inProgressAnnotation: Annotation? = nil
    @Published var selectedAnnotationID: UUID? = nil
    @Published var toolStyle = ToolStyle()
    /// Live context for the inset slider shown after an auto-center: the trimmed
    /// content (no whitespace), its synthesized fill, and the card on screen.
    @Published var autoCenter: AutoCenterContext?

    struct AutoCenterContext {
        var content: CGImage
        var fill: CGColor
        var inset: CGFloat
        var card: CGImage
        // Original→trimmed annotation shift (excl. inset), and the shift currently
        // applied to annotations. Lets the inset slider compose from scratch even
        // before an explicit center, gluing annotations correctly.
        var baseShift: CGSize = .zero
        var appliedShift: CGSize = .zero

        func bound(toCard card: CGImage) -> AutoCenterContext {
            var copy = self
            copy.card = card
            return copy
        }
    }

    struct ToolStyle {
        var arrowColor: CGColor = CGColor(red: 1, green: 0.23, blue: 0.19, alpha: 1)
        var arrowWeight: CGFloat = 4
        var lineColor: CGColor = CGColor(red: 1, green: 0.23, blue: 0.19, alpha: 1)
        var lineWeight: CGFloat = 4
        var lineDash: Annotation.LineDash = .solid
        var rectStroke: CGColor? = CGColor(red: 1, green: 0.23, blue: 0.19, alpha: 1)
        var rectFill: CGColor? = nil
        var rectWeight: CGFloat = 3
        var rectCorner: CGFloat = 6
        var textColor: CGColor = CGColor(red: 1, green: 0.23, blue: 0.19, alpha: 1)
        var textSize: CGFloat = 24
    }

    let undoStack = UndoStack()
    private let hitTolerance: CGFloat = 6
    private var moveStartKind: Annotation.Kind?

    init(document: EditorDocument, openingPanel: DocumentPanel = .none) {
        self.document = document
        self.originalDocument = document
        self.documentPanel = openingPanel
    }

    /// What the canvas renders: the original snapshot while previewing, else live edits.
    var displayDocument: EditorDocument { previewingOriginal ? originalDocument : document }

    /// True when edits differ from the original — enables reset/preview.
    var canReset: Bool { !document.hasSameEdits(as: originalDocument) }

    /// Revert all edits to the original, undoably, and exit preview.
    func resetToOriginal() {
        previewingOriginal = false
        guard canReset else { return }
        performCommand(ResetDocumentCommand(before: document, original: originalDocument))
    }

    /// Flip the compare-only preview of the original state.
    func togglePreviewOriginal() {
        guard canReset || previewingOriginal else { return }
        previewingOriginal.toggle()
    }

    func performUndo() {
        undoStack.undo(revert: { command in
            command.revert(to: &document)
            syncAutoCenter(afterReverting: command)
        })
        validateSelectedAnnotation()
    }

    func performRedo() {
        undoStack.redo(apply: { command in
            command.apply(to: &document)
            syncAutoCenter(afterApplying: command)
        })
        validateSelectedAnnotation()
    }

    func performCommand(_ command: EditorCommand) {
        undoStack.push(command, apply: { command in
            command.apply(to: &document)
            syncAutoCenter(afterApplying: command)
        })
        validateSelectedAnnotation()
    }

    private func syncAutoCenter(afterApplying command: EditorCommand) {
        if let command = command as? ApplyAutoCenterCommand {
            autoCenter = command.toAutoCenter?.bound(toCard: document.screenshot)
        } else {
            clearStaleAutoCenterContext()
        }
    }

    private func syncAutoCenter(afterReverting command: EditorCommand) {
        if let command = command as? ApplyAutoCenterCommand {
            autoCenter = command.fromAutoCenter?.bound(toCard: document.screenshot)
        } else {
            clearStaleAutoCenterContext()
        }
    }

    private func clearStaleAutoCenterContext() {
        if let autoCenter, autoCenter.card !== document.screenshot {
            self.autoCenter = nil
        }
    }

    /// Pick a canvas cursor mode (select / arrow / rectangle / text). Closes any pinned
    /// document panel. Picking a draw tool clears the current selection so the panel shows
    /// that tool's defaults.
    func selectCursorTool(_ tool: EditorTool) {
        guard tool.isEnabled, tool == .select || tool.isDrawTool else { return }
        activeTool = tool
        documentPanel = .none
        if tool.isDrawTool { deselect() }
    }

    /// Pin/unpin a document settings panel. Opening one returns the cursor to select and
    /// clears the selection so the panel is actually shown by the inspector route.
    func toggleDocumentPanel(_ panel: DocumentPanel) {
        if documentPanel == panel {
            documentPanel = .none
        } else {
            documentPanel = panel
            activeTool = .select
            deselect()
        }
    }

    /// Close the inspector: drop any pinned panel and selection, return cursor to select.
    func dismissInspector() {
        documentPanel = .none
        deselect()
        activeTool = .select
    }

    var inspectorRoute: InspectorRoute {
        switch documentPanel {
        case .canvas: return .canvas
        case .components:
            // Select mode: a chosen annotation shows its details (with a back path to
            // the list); otherwise the full component list.
            if inProgressTextDraft != nil { return .drawDefaults(.text) }
            return selectedAnnotation != nil ? .annotation : .componentList
        case .none:
            if selectedAnnotation != nil { return .annotation }
            if activeTool.isDrawTool { return .drawDefaults(activeTool) }
            return .hidden
        }
    }

    var isInspectorVisible: Bool { inspectorRoute != .hidden }

    var inspectorTitle: String {
        switch inspectorRoute {
        case .hidden: return ""
        case .componentList: return "Components"
        case .canvas: return "Canvas"
        case .drawDefaults(let tool): return tool.displayName
        case .annotation:
            switch selectedAnnotation?.kind {
            case .arrow: return "Arrow"
            case .line: return "Line"
            case .rect: return "Rectangle"
            case .text: return "Text"
            case .blur: return "Blur"
            case .none: return ""
            }
        }
    }

    var documentBounds: CGRect { document.annotationBounds }

    func beginDraw(at point: CGPoint) {
        let point = point.clamped(to: documentBounds)
        let kind: Annotation.Kind
        switch activeTool {
        case .arrow:
            kind = .arrow(from: point, to: point, color: toolStyle.arrowColor, weight: toolStyle.arrowWeight)
        case .line:
            kind = .line(from: point, to: point, color: toolStyle.lineColor, weight: toolStyle.lineWeight, dash: toolStyle.lineDash)
        case .rectangle:
            kind = .rect(
                frame: CGRect(origin: point, size: .zero),
                stroke: toolStyle.rectStroke,
                fill: toolStyle.rectFill,
                weight: toolStyle.rectWeight,
                cornerRadius: toolStyle.rectCorner
            )
        case .text:
            kind = .text(origin: point, string: "", fontSize: toolStyle.textSize, color: toolStyle.textColor)
        default:
            return
        }

        inProgressAnnotation = Annotation(kind: kind)
    }

    @discardableResult
    func beginTextDraft(at point: CGPoint) -> Annotation? {
        let point = point.clamped(to: documentBounds)
        let annotation = Annotation(
            kind: .text(
                origin: point,
                string: "",
                fontSize: toolStyle.textSize,
                color: toolStyle.textColor
            )
        )
        inProgressAnnotation = annotation
        selectedAnnotationID = nil
        activeTool = .text
        documentPanel = .none
        return annotation
    }

    func updateDraw(to point: CGPoint, shiftSnap: Bool) {
        guard let current = inProgressAnnotation else { return }
        let point = point.clamped(to: documentBounds)

        switch current.kind {
        case .arrow(let from, _, let color, let weight):
            let end = shiftSnap ? snap45(from: from, to: point) : point
            inProgressAnnotation?.kind = .arrow(from: from, to: end, color: color, weight: weight)
        case .line(let from, _, let color, let weight, let dash):
            let end = shiftSnap ? snap45(from: from, to: point) : snapNearAxis(from: from, to: point)
            inProgressAnnotation?.kind = .line(from: from, to: end, color: color, weight: weight, dash: dash)
        case .rect(let frame, let stroke, let fill, let weight, let corner):
            let origin = frame.origin
            var width = point.x - origin.x
            var height = point.y - origin.y
            if shiftSnap {
                let side = max(abs(width), abs(height))
                width = width < 0 ? -side : side
                height = height < 0 ? -side : side
            }
            let rect = CGRect(x: origin.x, y: origin.y, width: width, height: height)
            inProgressAnnotation?.kind = .rect(
                frame: rect.standardized.clamped(to: documentBounds),
                stroke: stroke,
                fill: fill,
                weight: weight,
                cornerRadius: corner
            )
        default:
            break
        }
    }

    @discardableResult
    func commitDraw() -> Annotation? {
        guard let annotation = inProgressAnnotation else { return nil }
        inProgressAnnotation = nil

        if isDegenerate(annotation.kind) {
            if case .text = annotation.kind {
                // A click-created text annotation is valid; the text editor will fill it.
            } else {
                return nil
            }
        }

        performCommand(AddAnnotationCommand(annotation: annotation))
        selectedAnnotationID = annotation.id
        activeTool = .select
        // Land in the Select inspector showing the new annotation's details; "back"
        // then returns to the full component list.
        documentPanel = .components
        return annotation
    }

    func cancelDraw() {
        inProgressAnnotation = nil
    }

    @discardableResult
    func commitTextDraft(id: UUID, string: String) -> Annotation? {
        guard let draft = inProgressAnnotation,
              draft.id == id,
              case let .text(origin, _, fontSize, color) = draft.kind else {
            return nil
        }

        let annotation = Annotation(
            id: id,
            kind: .text(origin: origin, string: string, fontSize: fontSize, color: color)
        )
        inProgressAnnotation = nil
        performCommand(AddAnnotationCommand(annotation: annotation))
        selectedAnnotationID = annotation.id
        activeTool = .select
        documentPanel = .components
        return annotation
    }

    func discardTextDraft(id: UUID) {
        if inProgressAnnotation?.id == id {
            inProgressAnnotation = nil
        }
        if selectedAnnotationID == id {
            selectedAnnotationID = nil
        }
    }

    func updateTextDraftStyle(fontSize: CGFloat, color: CGColor) {
        guard var draft = inProgressTextDraft,
              case let .text(origin, string, _, _) = draft.kind else {
            return
        }

        draft.kind = .text(origin: origin, string: string, fontSize: fontSize, color: color)
        inProgressAnnotation = draft
    }

    func beginMoveTextDraft(id: UUID) {
        guard let draft = inProgressTextDraft, draft.id == id else { return }
        moveStartKind = draft.kind
    }

    func moveTextDraft(by delta: CGSize) {
        guard var draft = inProgressTextDraft,
              let start = moveStartKind else {
            return
        }

        draft.kind = AnnotationGeometry.translatedClamped(start, by: delta, to: documentBounds)
        inProgressAnnotation = draft
    }

    func commitMoveTextDraft() {
        moveStartKind = nil
    }

    func annotationID(at point: CGPoint) -> UUID? {
        for annotation in document.annotations.reversed() {
            if AnnotationGeometry.hitTest(annotation.kind, point: point, tolerance: hitTolerance) {
                return annotation.id
            }
        }
        return nil
    }

    func selectAnnotation(at point: CGPoint) {
        selectedAnnotationID = annotationID(at: point)
    }

    func selectComponent(_ id: UUID) {
        guard document.annotations.contains(where: { $0.id == id }) else { return }
        cancelDraw()
        selectedAnnotationID = id
        activeTool = .select
        documentPanel = .components
    }

    func deselect() {
        selectedAnnotationID = nil
    }

    func beginMoveSelected() {
        guard let annotation = selectedAnnotation else { return }
        moveStartKind = annotation.kind
    }

    /// Live-move the selected annotation by a cumulative delta from the move start.
    func moveSelected(by delta: CGSize) {
        guard let id = selectedAnnotationID,
              let start = moveStartKind,
              let index = document.annotations.firstIndex(where: { $0.id == id }) else { return }

        document.annotations[index].kind = AnnotationGeometry.translatedClamped(start, by: delta, to: documentBounds)
    }

    func commitMoveSelected() {
        guard let id = selectedAnnotationID,
              let start = moveStartKind,
              let index = document.annotations.firstIndex(where: { $0.id == id }) else {
            moveStartKind = nil
            return
        }

        let end = document.annotations[index].kind
        moveStartKind = nil
        guard end != start else { return }

        document.annotations[index].kind = start
        performCommand(MoveAnnotationCommand(id: id, from: start, to: end))
    }

    func deleteSelectedAnnotation() {
        guard let id = selectedAnnotationID,
              let index = document.annotations.firstIndex(where: { $0.id == id }) else {
            selectedAnnotationID = nil
            return
        }

        let annotation = document.annotations[index]
        performCommand(RemoveAnnotationCommand(annotation: annotation, index: index))
        selectedAnnotationID = nil
    }

    func updateSelectedKind(
        _ newKind: Annotation.Kind,
        coalescingKey: AnnotationEditCoalescingKey? = nil
    ) {
        guard let id = selectedAnnotationID,
              let index = document.annotations.firstIndex(where: { $0.id == id }) else { return }
        let from = document.annotations[index].kind
        guard from != newKind else { return }

        performCommand(MoveAnnotationCommand(id: id, from: from, to: newKind, coalescingKey: coalescingKey))
    }

    func nudgeSelected(by delta: CGSize) {
        guard let annotation = selectedAnnotation else { return }
        let nextKind = AnnotationGeometry.translatedClamped(annotation.kind, by: delta, to: documentBounds)
        updateSelectedKind(nextKind, coalescingKey: .keyboardNudge)
    }

    var selectedAnnotation: Annotation? {
        guard let id = selectedAnnotationID else { return nil }
        return document.annotations.first { $0.id == id }
    }

    var inProgressTextDraft: Annotation? {
        guard let annotation = inProgressAnnotation,
              case .text = annotation.kind else {
            return nil
        }
        return annotation
    }

    private func validateSelectedAnnotation() {
        guard let id = selectedAnnotationID else { return }
        if !document.annotations.contains(where: { $0.id == id }) {
            selectedAnnotationID = nil
        }
    }

    private func isDegenerate(_ kind: Annotation.Kind) -> Bool {
        switch kind {
        case .arrow(let from, let to, _, _), .line(let from, let to, _, _, _):
            return hypot(to.x - from.x, to.y - from.y) < 3
        case .rect(let frame, _, _, _, _):
            return frame.width < 3 || frame.height < 3
        default:
            return false
        }
    }

    /// Auto-lock to horizontal or vertical when the segment is within ~7° of an
    /// axis — so underlines straighten without holding a modifier.
    private func snapNearAxis(from: CGPoint, to: CGPoint) -> CGPoint {
        let dx = to.x - from.x
        let dy = to.y - from.y
        guard hypot(dx, dy) > 0.0001 else { return to }
        let threshold = 7.0 * .pi / 180
        let angle = atan2(abs(dy), abs(dx))
        if angle <= threshold { return CGPoint(x: to.x, y: from.y) }
        if angle >= .pi / 2 - threshold { return CGPoint(x: from.x, y: to.y) }
        return to
    }

    private func snap45(from: CGPoint, to: CGPoint) -> CGPoint {
        let dx = to.x - from.x
        let dy = to.y - from.y
        let angle = atan2(dy, dx)
        let snapped = (angle / (.pi / 4)).rounded() * (.pi / 4)
        let length = hypot(dx, dy)
        return CGPoint(x: from.x + cos(snapped) * length, y: from.y + sin(snapped) * length)
    }
}

private extension CGPoint {
    func clamped(to rect: CGRect) -> CGPoint {
        CGPoint(
            x: min(max(x, rect.minX), rect.maxX),
            y: min(max(y, rect.minY), rect.maxY)
        )
    }
}

private extension CGRect {
    func clamped(to bounds: CGRect) -> CGRect {
        let width = min(self.width, bounds.width)
        let height = min(self.height, bounds.height)
        let x = min(max(minX, bounds.minX), bounds.maxX - width)
        let y = min(max(minY, bounds.minY), bounds.maxY - height)
        return CGRect(x: x, y: y, width: width, height: height)
    }
}
