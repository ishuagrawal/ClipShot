import SwiftUI

/// Right-hand inspector: a loose column of floating glass cards over the stage.
/// Contextual cards (selection, tool defaults) surface at the top when relevant;
/// Layers, Frame, and Background are always present, always in the same order.
struct InspectorView: View {
    @ObservedObject var state: EditorState
    var onCanvasFocusRequested: () -> Void = {}

    var body: some View {
        VStack(spacing: 10) {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 10) {
                    if state.selectedAnnotation != nil {
                        selectionCard
                    } else if state.activeTool.isDrawTool || state.inProgressTextDraft != nil {
                        toolDefaultsCard
                    }
                    layersCard
                    GlassCard("Frame") {
                        PaddingToolView(state: state)
                    }
                    GlassCard("Background") {
                        BackgroundToolView(state: state)
                    }
                }
                .padding(.vertical, 2)
                // Side gutters keep card shadows inside the clipped scroll bounds.
                .padding(.horizontal, 16)
            }
            .defaultScrollAnchor(.top)

            ExportPanelView(state: state)
        }
        .frame(width: Theme.inspectorWidth + 32)
    }

    private var selectionCard: some View {
        GlassCard(selectionTitle) {
            IconButton(systemName: "trash") { state.deleteSelectedAnnotation() }
                .help("Delete annotation")
                .accessibilityLabel("Delete annotation")
        } content: {
            SelectToolView(state: state)
        }
    }

    private var toolDefaultsCard: some View {
        let tool = state.inProgressTextDraft != nil ? EditorTool.text : state.activeTool
        return GlassCard("\(tool.displayName) defaults") {
            switch tool {
            case .arrow:     ArrowToolView(state: state)
            case .rectangle: RectangleToolView(state: state)
            case .text:      TextToolView(state: state)
            default:         EmptyView()
            }
        }
    }

    private var layersCard: some View {
        GlassCard("Layers") {
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
