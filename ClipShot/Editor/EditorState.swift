import Combine
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

    /// P0: only Select is enabled. Others are scaffolded but inert.
    var isEnabledInP0: Bool { self == .select }

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
        case .select:     return ""
        case .padding:    return "Coming in P1"
        case .background: return "Coming in P1"
        case .arrow:      return "Coming in P2"
        case .rectangle:  return "Coming in P2"
        case .text:       return "Coming in P2"
        case .blur:       return "Coming in P3"
        }
    }
}

@MainActor
final class EditorState: ObservableObject {
    @Published var document: EditorDocument
    @Published var activeTool: EditorTool = .select
    /// In-progress annotation being drawn. Unused in P0 (always nil).
    @Published var inProgressAnnotation: Annotation? = nil
    /// Selected annotation id. Unused in P0.
    @Published var selectedAnnotationID: UUID? = nil

    let undoStack = UndoStack()

    init(document: EditorDocument) {
        self.document = document
    }

    func performUndo() {
        undoStack.undo(revert: { $0.revert(to: &document) })
    }

    func performRedo() {
        undoStack.redo(apply: { $0.apply(to: &document) })
    }

    func performCommand(_ command: EditorCommand) {
        undoStack.push(command, apply: { $0.apply(to: &document) })
    }
}
