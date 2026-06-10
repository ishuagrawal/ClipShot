import SwiftUI

/// Right-hand inspector: a fixed stack of collapsible sections, always visible.
/// No routing, no back/close chrome — what you can edit is always where it was.
/// Contextual sections (selection, tool defaults) appear at the top when relevant.
struct InspectorView: View {
    @ObservedObject var state: EditorState
    var onCanvasFocusRequested: () -> Void = {}

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                if state.selectedAnnotation != nil {
                    selectionSection
                } else if state.activeTool.isDrawTool || state.inProgressTextDraft != nil {
                    toolDefaultsSection
                }
                layersSection
                InspectorSection("Frame") {
                    PaddingToolView(state: state)
                }
                InspectorSection("Background") {
                    BackgroundToolView(state: state)
                }
            }
        }
        .frame(width: Theme.sidebarWidth)
        .background(Theme.surface)
        .overlay(alignment: .leading) {
            Rectangle().fill(Theme.hairline).frame(width: 1)
        }
    }

    private var selectionSection: some View {
        InspectorSection(selectionTitle) {
            IconButton(systemName: "trash") { state.deleteSelectedAnnotation() }
                .help("Delete annotation")
                .accessibilityLabel("Delete annotation")
        } content: {
            SelectToolView(state: state)
        }
    }

    private var toolDefaultsSection: some View {
        let tool = state.inProgressTextDraft != nil ? EditorTool.text : state.activeTool
        return InspectorSection("\(tool.displayName) defaults") {
            switch tool {
            case .arrow:     ArrowToolView(state: state)
            case .rectangle: RectangleToolView(state: state)
            case .text:      TextToolView(state: state)
            default:         EmptyView()
            }
        }
    }

    private var layersSection: some View {
        InspectorSection("Layers") {
            if !state.document.annotations.isEmpty {
                Text("\(state.document.annotations.count)")
                    .font(Theme.mono(11, .semibold))
                    .foregroundStyle(Theme.textTertiary)
            }
        } content: {
            ComponentListView(
                state: state,
                onCanvasFocusRequested: onCanvasFocusRequested
            )
        }
    }

    private var selectionTitle: String {
        switch state.selectedAnnotation?.kind {
        case .arrow: return "Arrow"
        case .rect:  return "Rectangle"
        case .text:  return "Text"
        case .blur:  return "Blur"
        case .none:  return ""
        }
    }
}
