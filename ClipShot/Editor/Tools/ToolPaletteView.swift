import SwiftUI

/// Floating glass tool pod, vertically centered on the left edge — the single
/// home for every cursor tool. Picking a draw tool sets the canvas cursor mode;
/// finishing a draw auto-returns to Select (see `EditorState.commitDraw`).
struct ToolPodView: View {
    @ObservedObject var state: EditorState

    private let tools: [(EditorTool, String?)] = [
        (.select, "V"),
        (.arrow, "A"),
        (.rectangle, "R"),
        (.text, "T")
    ]

    var body: some View {
        VStack(spacing: 4) {
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
        }
        .padding(8)
        .glassPanel(cornerRadius: 26)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Tools")
    }
}
