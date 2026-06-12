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
        (.rectangle, "R"),
        (.text, "T")
    ]

    var body: some View {
        HStack(spacing: 4) {
            IconButton(systemName: "arrow.uturn.backward") { state.performUndo() }
                .accessibilityLabel("Undo")
                .disabled(!state.undoStack.canUndo)
                .opacity(state.undoStack.canUndo ? 1 : 0.35)
                .help("Undo")

            IconButton(systemName: "arrow.uturn.forward") { state.performRedo() }
                .accessibilityLabel("Redo")
                .disabled(!state.undoStack.canRedo)
                .opacity(state.undoStack.canRedo ? 1 : 0.35)
                .help("Redo")

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
            }

            divider

            ZoomControlsView(zoom: zoom)
        }
        .padding(.horizontal, 12)
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
}
