import SwiftUI

/// Right-hand inspector: a loose column of floating glass cards over the stage,
/// always the same three — Layers, Frame, Background. Annotation styling lives
/// in the left `AnnotationPanelView` so document properties never jump around.
struct InspectorView: View {
    @ObservedObject var state: EditorState
    var onCanvasFocusRequested: () -> Void = {}

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 10) {
                layersCard
                GlassCard("Frame") {
                    PaddingToolView(state: state)
                }
                GlassCard("Background") {
                    BackgroundToolView(state: state)
                }
            }
            .padding(.vertical, 2)
            .padding(.horizontal, 16)
        }
        .defaultScrollAnchor(.top)
        // Cards blur and fade at the scroll bounds instead of hard-clipping. The
        // clear safe-area bars mark where those soft edges live (clear of the
        // window top and the bottom edge); the outer ignoresSafeArea strips
        // safeAreaPadding, so explicit inset bars are used instead.
        .softVerticalScrollEdges()
        .safeAreaInset(edge: .top, spacing: 0) {
            Color.clear.frame(height: 52)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            Color.clear.frame(height: Theme.chromeMargin)
        }
        .frame(width: Theme.inspectorWidth + 32)
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
}

/// Left annotation panel: a single floating squircle of glass that appears when
/// an annotation is selected or a draw tool is armed, carrying that shape's
/// style controls. Gone when there is nothing to style — the stage stays clear.
struct AnnotationPanelView: View {
    @ObservedObject var state: EditorState

    var body: some View {
        Group {
            if state.selectedAnnotation != nil {
                GlassCard(selectionTitle) {
                    IconButton(systemName: "trash") { state.deleteSelectedAnnotation() }
                        .help("Delete annotation")
                        .accessibilityLabel("Delete annotation")
                } content: {
                    SelectToolView(state: state)
                }
            } else if state.activeTool.isDrawTool || state.inProgressTextDraft != nil {
                GlassCard("\(activeDrawTool.displayName) defaults") {
                    toolDefaults
                }
            }
        }
        .animation(.easeOut(duration: 0.15), value: state.selectedAnnotationID)
        .animation(.easeOut(duration: 0.15), value: state.activeTool)
    }

    private var activeDrawTool: EditorTool {
        state.inProgressTextDraft != nil ? .text : state.activeTool
    }

    @ViewBuilder
    private var toolDefaults: some View {
        switch activeDrawTool {
        case .arrow:     ArrowToolView(state: state)
        case .rectangle: RectangleToolView(state: state)
        case .text:      TextToolView(state: state)
        default:         EmptyView()
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
