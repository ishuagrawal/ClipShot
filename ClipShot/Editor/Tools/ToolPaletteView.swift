import SwiftUI

/// The dock: one floating glass bar under the stage — history, cursor tools,
/// and zoom, separated by hairlines, in working order left to right. Picking a
/// draw tool sets the canvas cursor mode; finishing a draw auto-returns to
/// Select (see `EditorState.commitDraw`). Export actions live in the top bar.
struct DockView: View {
    @ObservedObject var state: EditorState
    @ObservedObject var zoom: CanvasZoomController

    private let tools: [(EditorTool, String?)] = [
        (.select, "V"),
        (.arrow, "A"),
        (.line, "L"),
        (.rectangle, "R"),
        (.text, "T")
    ]

    var body: some View {
        HStack(spacing: 4) {
            let undoEnabled = state.undoStack.canUndo && !state.previewingOriginal
            let redoEnabled = state.undoStack.canRedo && !state.previewingOriginal
            let resetEnabled = state.canReset && !state.previewingOriginal

            IconButton(systemName: "arrow.uturn.backward") { state.performUndo() }
                .accessibilityLabel("Undo")
                .disabled(!undoEnabled)
                .opacity(undoEnabled ? 1 : 0.35)
                .help("Undo")

            IconButton(systemName: "arrow.uturn.forward") { state.performRedo() }
                .accessibilityLabel("Redo")
                .disabled(!redoEnabled)
                .opacity(redoEnabled ? 1 : 0.35)
                .help("Redo")

            subDivider

            IconButton(systemName: "arrow.counterclockwise") { state.resetToOriginal() }
                .accessibilityLabel("Reset to Original")
                .disabled(!resetEnabled)
                .opacity(resetEnabled ? 1 : 0.35)
                .help("Reset to Original")

            ToolRailButton(
                systemName: "eye",
                label: "Preview Original",
                shortcut: nil,
                isActive: state.previewingOriginal
            ) {
                state.togglePreviewOriginal()
            }
            .disabled(!state.canReset && !state.previewingOriginal)
            .opacity(state.canReset || state.previewingOriginal ? 1 : 0.35)

            divider

            ForEach(tools, id: \.0) { tool, shortcut in
                ToolRailButton(
                    systemName: tool.symbolName,
                    label: tool.displayName,
                    shortcut: shortcut,
                    isActive: state.activeTool == tool
                ) {
                    state.selectCursorTool(tool)
                }
                .disabled(state.previewingOriginal)
                .opacity(state.previewingOriginal ? 0.35 : 1)
            }

            divider

            ZoomControlsView(zoom: zoom)
        }
        .padding(.horizontal, Theme.barInset)
        .frame(height: Theme.dockHeight)
        .glassPanel(cornerRadius: 26)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Dock")
    }

    private var divider: some View {
        Rectangle()
            .fill(Theme.hairlineStrong)
            .frame(width: 1, height: 18)
            .padding(.horizontal, 7)
    }

    private var subDivider: some View {
        Rectangle()
            .fill(Theme.hairline)
            .frame(width: 1, height: 14)
            .padding(.horizontal, 6)
    }
}
