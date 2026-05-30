import Combine
import CoreGraphics
import Foundation

enum EditorTool: String, CaseIterable, Identifiable {
    case select
    case padding
    case background
    case arrow
    case rectangle
    case text
    case blur

    var id: String { rawValue }

    /// Tools shipped so far: Select (P0), Padding + Background (P1), Arrow/Rect/Text (P2).
    var isEnabled: Bool {
        switch self {
        case .select, .padding, .background, .arrow, .rectangle, .text:
            return true
        case .blur:
            return false
        }
    }

    /// Select appears as a tab even without a static panel, because it is the gateway
    /// to selecting, moving, and deleting annotations.
    var isToolbarTab: Bool {
        isEnabled && (hasDetailPanel || self == .select)
    }

    var isDrawTool: Bool {
        switch self {
        case .arrow, .rectangle, .text, .blur:
            return true
        case .select, .padding, .background:
            return false
        }
    }

    /// Whether this tool exposes controls in the sidebar detail panel.
    var hasDetailPanel: Bool {
        switch self {
        case .select:
            return false
        case .padding, .background, .arrow, .rectangle, .text, .blur:
            return true
        }
    }

    var symbolName: String {
        switch self {
        case .select:     return "cursorarrow"
        case .padding:    return "square.dashed"
        case .background: return "paintpalette"
        case .arrow:      return "arrow.up.right"
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
        case .rectangle:  return "Rectangle"
        case .text:       return "Text"
        case .blur:       return "Blur / Redact"
        }
    }

    var comingSoonNote: String {
        switch self {
        case .select, .padding, .background, .arrow, .rectangle, .text:
            return ""
        case .blur:       return "Coming in P3"
        }
    }
}

@MainActor
final class EditorState: ObservableObject {
    @Published var document: EditorDocument
    @Published var activeTool: EditorTool = .select
    @Published var isDetailPanelExpanded: Bool = true
    @Published var inProgressAnnotation: Annotation? = nil
    @Published var selectedAnnotationID: UUID? = nil
    @Published var toolStyle = ToolStyle()

    struct ToolStyle {
        var arrowColor: CGColor = CGColor(red: 1, green: 0.23, blue: 0.19, alpha: 1)
        var arrowWeight: CGFloat = 4
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

    init(document: EditorDocument, initialTool: EditorTool = .select) {
        self.document = document
        if initialTool.isEnabled {
            activeTool = initialTool
            isDetailPanelExpanded = initialTool.hasDetailPanel
        }
    }

    func performUndo() {
        undoStack.undo(revert: { $0.revert(to: &document) })
        validateSelectedAnnotation()
    }

    func performRedo() {
        undoStack.redo(apply: { $0.apply(to: &document) })
        validateSelectedAnnotation()
    }

    func performCommand(_ command: EditorCommand) {
        undoStack.push(command, apply: { $0.apply(to: &document) })
        validateSelectedAnnotation()
    }

    /// Selecting a new enabled tool activates it and expands its panel; re-selecting
    /// the active tool toggles the panel. Disabled tools are ignored.
    func selectTool(_ tool: EditorTool) {
        guard tool.isEnabled else { return }
        if activeTool == tool {
            if tool.hasDetailPanel {
                isDetailPanelExpanded.toggle()
            }
        } else {
            activeTool = tool
            isDetailPanelExpanded = true
        }
    }

    func toggleDetailPanel() {
        if activeTool == .select {
            deselect()
            return
        }
        isDetailPanelExpanded.toggle()
    }

    var isDetailPanelVisible: Bool {
        if activeTool == .select {
            return selectedAnnotation != nil
        }
        return activeTool.hasDetailPanel && isDetailPanelExpanded
    }

    var documentBounds: CGRect {
        CGRect(origin: .zero, size: document.paddedDocumentSize)
    }

    func beginDraw(at point: CGPoint) {
        let point = point.clamped(to: documentBounds)
        let kind: Annotation.Kind
        switch activeTool {
        case .arrow:
            kind = .arrow(from: point, to: point, color: toolStyle.arrowColor, weight: toolStyle.arrowWeight)
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

    func updateDraw(to point: CGPoint, shiftSnap: Bool) {
        guard let current = inProgressAnnotation else { return }
        let point = point.clamped(to: documentBounds)

        switch current.kind {
        case .arrow(let from, _, let color, let weight):
            let end = shiftSnap ? snap45(from: from, to: point) : point
            inProgressAnnotation?.kind = .arrow(from: from, to: end, color: color, weight: weight)
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
        return annotation
    }

    func cancelDraw() {
        inProgressAnnotation = nil
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

        document.annotations[index].kind = AnnotationGeometry.clamped(
            AnnotationGeometry.translated(start, by: delta),
            to: documentBounds
        )
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

    var selectedAnnotation: Annotation? {
        guard let id = selectedAnnotationID else { return nil }
        return document.annotations.first { $0.id == id }
    }

    private func validateSelectedAnnotation() {
        guard let id = selectedAnnotationID else { return }
        if !document.annotations.contains(where: { $0.id == id }) {
            selectedAnnotationID = nil
        }
    }

    private func isDegenerate(_ kind: Annotation.Kind) -> Bool {
        switch kind {
        case .arrow(let from, let to, _, _):
            return hypot(to.x - from.x, to.y - from.y) < 3
        case .rect(let frame, _, _, _, _):
            return frame.width < 3 || frame.height < 3
        default:
            return false
        }
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
