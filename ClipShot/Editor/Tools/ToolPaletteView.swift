import SwiftUI

/// Floating drawing-tools palette, centred at the top of the canvas. Arrow / Rectangle /
/// Text — the annotation tools. Picking one sets the canvas cursor mode; finishing a draw
/// auto-returns to Select and opens the component inspector (see `EditorState.commitDraw`).
/// Select itself lives in the top bar (`TopToolBarView`), not here.
struct ToolPaletteView: View {
    @ObservedObject var state: EditorState

    private let tools: [EditorTool] = [.arrow, .rectangle, .text]

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
