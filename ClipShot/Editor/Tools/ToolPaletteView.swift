import SwiftUI

/// The dock: a compact floating glass bar under the stage holding the in-canvas
/// hands only — cursor tools and zoom. Document-level commands live in the top
/// bar. Picking a draw tool sets the canvas cursor mode; finishing a draw
/// auto-returns to Select (see `EditorState.commitDraw`).
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
        .padding(.horizontal, 10)
        .frame(height: 52)
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
