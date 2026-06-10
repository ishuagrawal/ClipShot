import SwiftUI

/// Fixed left tool rail — the single home for every cursor tool. Select plus the
/// annotation tools, top-aligned, full height. Picking a draw tool sets the canvas
/// cursor mode; finishing a draw auto-returns to Select (see `EditorState.commitDraw`).
struct ToolRailView: View {
    @ObservedObject var state: EditorState

    private let tools: [(EditorTool, String?)] = [
        (.select, "V"),
        (.arrow, "A"),
        (.rectangle, "R"),
        (.text, "T")
    ]

    var body: some View {
        VStack(spacing: 6) {
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
            Spacer()
        }
        .padding(.top, 12)
        .frame(width: 52)
        .frame(maxHeight: .infinity)
        .background(Theme.surface)
        .overlay(alignment: .trailing) {
            Rectangle().fill(Theme.hairline).frame(width: 1)
        }
    }
}
