import SwiftUI

/// Right-hand inspector: a loose column of floating glass cards over the stage.
/// Contextual cards (selection, tool defaults) surface at the top when relevant;
/// Layers, Frame, and Background are always present, always in the same order.
struct InspectorView: View {
    @ObservedObject var state: EditorState
    @Environment(\.inspectorWidth) private var inspectorWidth
    var onCanvasFocusRequested: () -> Void = {}
    /// Last measured height of the contextual interior. Sticky on purpose: the
    /// slot's frame derives from `hasContextCard ? this : 0`, so open/close is
    /// a pure function of state and survives arbitrarily fast tool toggling —
    /// no transition or geometry callback has to refire for the panel to come
    /// back. A stale value only persists while the slot is collapsed; the next
    /// interior re-measures on its way in.
    @State private var contextCardHeight: CGFloat = 0
    @State private var interiorOpacity: Double = 1

    var body: some View {
        ScrollView(showsIndicators: false) {
            // Group the cards' glass effects into one backdrop-sampling pass;
            // separate effects each re-blur the canvas every scroll frame.
            glassGroupedColumn
                .padding(.vertical, 2)
                .padding(.horizontal, Theme.panelInset)
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
        .frame(width: inspectorWidth + Theme.panelInset * 2)
    }

    @ViewBuilder
    private var glassGroupedColumn: some View {
        if #available(macOS 26.0, *) {
            // Tight spacing: cards sit 10pt apart, and the default merge
            // distance lets their glass shapes coalesce and split while the
            // contextual panel resizes, which reads as flicker.
            GlassEffectContainer(spacing: 2) {
                cardColumn
            }
        } else {
            cardColumn
        }
    }

    /// Gap between inspector cards; also cancelled out below the collapsed
    /// contextual slot so the hidden slot leaves no double gap.
    private let columnSpacing: CGFloat = Theme.cardGap

    @ViewBuilder
    private var cardColumn: some View {
        VStack(alignment: .leading, spacing: columnSpacing) {
            // One permanent glass surface whose height springs between zero and
            // the measured height of the current interior — both opening and
            // closing shrink/grow the panel on the same spring that moves the
            // cards below, so nothing ever overlaps. The interiors (chromeless
            // GlassCards) crossfade inside it, clipped to the surface so content
            // is revealed as the panel grows rather than popping in full-size.
            // The glass fades via plain opacity: a blur transition would
            // rasterize the glassEffect inside the GlassEffectContainer and make
            // its content snap instead of riding the animation.
            ZStack(alignment: .top) {
                if hasContextCard {
                    contextCard
                        // Sequenced fade driven by state, not insert/remove
                        // transitions: on a swap the content cuts to the new
                        // interior at zero opacity and fades up, so half-opaque
                        // interiors never overlap (reads as a flash) and rapid
                        // tool swaps just retarget the animation — re-inserting
                        // a transitioning-out identity could leave the interior
                        // stuck invisible. Plain opacity, because blur on
                        // content rendered into a glassEffect causes flicker.
                        // .identity for the same reason: a default opacity
                        // removal lasts the length of the panel spring, and
                        // re-inserting the interior mid-removal (rapid select ↔
                        // draw-tool toggling) cancels the insertion and leaves
                        // the slot empty. The slot's height, opacity, and the
                        // state-driven fade already carry the visuals.
                        .transition(.identity)
                        .opacity(interiorOpacity)
                        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { height in
                            if contextCardHeight != height {
                                withAnimation(Theme.panelSpring) { contextCardHeight = height }
                            }
                        }
                }
            }
            .frame(height: hasContextCard ? contextCardHeight : 0, alignment: .top)
            .clipShape(RoundedRectangle(cornerRadius: Theme.radiusPanel, style: .continuous))
            .glassPanel()
            .opacity(hasContextCard ? 1 : 0)
            // Cancel the column spacing while collapsed so the hidden slot
            // doesn't leave a double gap above the Layers card.
            .padding(.bottom, hasContextCard ? 0 : -columnSpacing)
            .onChange(of: contextCardKey) { _, key in
                guard key != "none" else { return }
                var snap = Transaction()
                snap.disablesAnimations = true
                withTransaction(snap) { interiorOpacity = 0 }
                withAnimation(.easeOut(duration: 0.22).delay(0.05)) { interiorOpacity = 1 }
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

    private var hasContextCard: Bool {
        state.selectedAnnotation != nil
            || state.activeTool.isDrawTool
            || state.inProgressTextDraft != nil
    }

    @ViewBuilder
    private var contextCard: some View {
        if state.selectedAnnotation != nil {
            selectionCard
        } else {
            toolDefaultsCard
        }
    }

    /// Identity of the contextual card currently surfaced at the top of the
    /// column. Changing kind (or tool) swaps interiors through the sequenced
    /// fade while the panel resizes; reselecting another annotation of the
    /// same kind keeps the card in place and just updates its controls.
    private var contextCardKey: String {
        if state.selectedAnnotation != nil { return "selection:\(selectionTitle)" }
        if state.inProgressTextDraft != nil { return "defaults:text" }
        if state.activeTool.isDrawTool { return "defaults:\(state.activeTool.displayName)" }
        return "none"
    }

    private var selectionCard: some View {
        GlassCard(selectionTitle, glass: false) {
            SelectToolView(state: state)
        }
        // Top padding centers the 28pt button on the title's text line (13pt inset + ~6pt half line - 14).
        .overlay(alignment: .topTrailing) {
            IconButton(systemName: "trash", hoverColor: Theme.danger, hoverFill: Theme.danger) {
                state.deleteSelectedAnnotation()
            }
            .help("Delete annotation")
            .accessibilityLabel("Delete annotation")
            .padding([.top, .trailing], 5)
        }
    }

    private var toolDefaultsCard: some View {
        let tool = state.inProgressTextDraft != nil ? EditorTool.text : state.activeTool
        return GlassCard(tool.displayName, glass: false) {
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

