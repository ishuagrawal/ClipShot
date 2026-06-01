import SwiftUI

/// Floating drawing-mode palette, centred at the top of the canvas. The only control with
/// an active-mode highlight. Picking a tool sets the canvas cursor mode; finishing a draw
/// auto-returns to Select (see `CanvasInteractionView` / `EditorState.commitDraw`).
struct ToolPaletteView: View {
    @ObservedObject var state: EditorState

    private let tools: [EditorTool] = [.select, .arrow, .rectangle, .text]

    var body: some View {
        HStack(spacing: 4) {
            ForEach(tools) { tool in
                ToolPaletteButton(
                    systemName: tool.symbolName,
                    label: tool.displayName,
                    isActive: state.activeTool == tool
                ) {
                    state.selectCursorTool(tool)
                }
            }
        }
        .padding(5)
        .floatingBar(cornerRadius: Theme.radiusPill)
    }
}
