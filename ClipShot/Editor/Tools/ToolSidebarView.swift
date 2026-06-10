import SwiftUI

/// Right-hand inspector: a loose column of floating glass cards over the stage.
/// Contextual cards (selection, tool defaults) surface at the top when relevant;
/// Layers, Frame, and Background are always present, always in the same order.
struct InspectorView: View {
    @ObservedObject var state: EditorState
    var onCanvasFocusRequested: () -> Void = {}

    var body: some View {
        ScrollView(showsIndicators: false) {
            Group {
                // One shared glass container: the cards' effects merge into a
                // single backdrop sampling pass instead of one per card, which
                // keeps panning the canvas underneath cheap.
                if #available(macOS 26.0, *) {
                    GlassEffectContainer(spacing: 10) { cardColumn }
                } else {
                    cardColumn
                }
            }
            .padding(.vertical, 2)
            .padding(.horizontal, 16)
        }
        .defaultScrollAnchor(.top)
        // Cards blur and fade at the scroll bounds instead of hard-clipping. The
        // clear safe-area bars mark where those soft edges live — the same
        // elevation top and bottom, sized so cards finish fading before they
        // would slide under the dock (52pt bar + its margin). The outer
        // ignoresSafeArea strips safeAreaPadding, so explicit inset bars are
        // used instead.
        .softVerticalScrollEdges()
        .safeAreaInset(edge: .top, spacing: 0) {
            Color.clear.frame(height: Theme.scrollFadeInset)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            Color.clear.frame(height: Theme.scrollFadeInset)
        }
        // The soft scroll-edge effect alone leaves cards fully opaque at the
        // window border; this mask guarantees they finish dissolving while
        // still clear of the dock zone, top and bottom alike.
        .mask {
            VStack(spacing: 0) {
                Color.clear.frame(height: Theme.scrollFadeClear)
                LinearGradient(colors: [.clear, .black],
                               startPoint: .top, endPoint: .bottom)
                    .frame(height: Theme.scrollFadeBand)
                Rectangle().fill(.black)
                LinearGradient(colors: [.black, .clear],
                               startPoint: .top, endPoint: .bottom)
                    .frame(height: Theme.scrollFadeBand)
                Color.clear.frame(height: Theme.scrollFadeClear)
            }
        }
        .frame(width: Theme.inspectorWidth + 32)
    }

    @ViewBuilder
    private var cardColumn: some View {
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

    private var selectionTitle: String {
        switch state.selectedAnnotation?.kind {
        case .arrow: return "Arrow"
        case .rect:  return "Rectangle"
        case .text:  return "Text"
        case .blur:  return "Blur"
        case .none:  return ""
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
}

