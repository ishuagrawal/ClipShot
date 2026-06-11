import SwiftUI

/// Right-hand inspector: a loose column of floating glass cards over the stage.
/// Contextual cards (selection, tool defaults) surface at the top when relevant;
/// Layers, Frame, and Background are always present, always in the same order.
struct InspectorView: View {
    @ObservedObject var state: EditorState
    @Environment(\.inspectorWidth) private var inspectorWidth
    var onCanvasFocusRequested: () -> Void = {}

    var body: some View {
        ScrollView(showsIndicators: false) {
            cardColumn
                .padding(.vertical, 2)
                .padding(.horizontal, 16)
        }
        .defaultScrollAnchor(.top)
        // Cards blur and fade at the scroll bounds instead of hard-clipping. The
        // clear safe-area bars mark where those soft edges live — the same gap
        // against the top control bar and the dock line, so the column reads
        // vertically centered in the working area. The bottom bar is deeper by
        // bottomChromeHeight because its reference line (the dock) floats above
        // the window edge, while the top reference (the control bar) is already
        // absorbed by the overlay's topChromeHeight padding. The outer
        // ignoresSafeArea strips safeAreaPadding, so explicit inset bars are
        // used instead.
        .softVerticalScrollEdges()
        .safeAreaInset(edge: .top, spacing: 0) {
            Color.clear.frame(height: Theme.scrollFadeTopInset)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            Color.clear.frame(height: Theme.scrollFadeBottomInset)
        }
        // The soft scroll-edge effect alone leaves cards fully opaque at the
        // window border; this mask guarantees they finish dissolving the same
        // distance from the top bar as from the dock line.
        .mask {
            VStack(spacing: 0) {
                LinearGradient(colors: [.clear, .black],
                               startPoint: .top, endPoint: .bottom)
                    .frame(height: Theme.scrollFadeBand)
                Rectangle().fill(.black)
                LinearGradient(colors: [.black, .clear],
                               startPoint: .top, endPoint: .bottom)
                    .frame(height: Theme.scrollFadeBand)
                Color.clear.frame(height: Theme.scrollFadeBottomInset - Theme.scrollFadeBand)
            }
        }
        .frame(width: inspectorWidth + 32)
    }

    @ViewBuilder
    private var cardColumn: some View {
        VStack(alignment: .leading, spacing: 10) {
            if state.selectedAnnotation != nil {
                selectionCard
                    .id(contextCardKey)
                    .transition(.liquidPanel)
            } else if state.activeTool.isDrawTool || state.inProgressTextDraft != nil {
                toolDefaultsCard
                    .id(contextCardKey)
                    .transition(.liquidPanel)
            }
            layersCard
            GlassCard("Frame") {
                PaddingToolView(state: state)
            }
            GlassCard("Background") {
                BackgroundToolView(state: state)
            }
        }
        // The contextual card condenses in and dissolves out; the permanent
        // cards below flow down/up on the same spring instead of snapping.
        .animation(Theme.panelSpring, value: contextCardKey)
    }

    /// Identity of the contextual card currently surfaced at the top of the
    /// column. Changing kind (or tool) swaps cards through the liquid
    /// transition; reselecting another annotation of the same kind keeps the
    /// card in place and just updates its controls.
    private var contextCardKey: String {
        if state.selectedAnnotation != nil { return "selection:\(selectionTitle)" }
        if state.inProgressTextDraft != nil { return "defaults:text" }
        if state.activeTool.isDrawTool { return "defaults:\(state.activeTool.displayName)" }
        return "none"
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

