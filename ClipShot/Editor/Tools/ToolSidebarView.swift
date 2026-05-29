import SwiftUI

/// Left sidebar: the configuration panel for whichever tool is active in the top tool bar.
/// It owns a header (tool name + collapse) and the tool's controls; tool *selection* now
/// lives in `TopToolBarView`, so there is no icon rail here anymore.
struct ToolSidebarView: View {
    @ObservedObject var state: EditorState

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Rectangle().fill(Theme.hairline).frame(height: 1)
            ScrollView {
                controls
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .frame(width: 280)
        .background(Theme.surface)
        .overlay(alignment: .trailing) {
            Rectangle().fill(Theme.edgeShadow).frame(width: 1)
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: state.activeTool.symbolName)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Theme.accentText)
            Text(TopToolBarView.tabLabel(state.activeTool))
                .font(Theme.label(15, .semibold))
                .foregroundStyle(Theme.textPrimary)
            Spacer()
            Button {
                state.toggleDetailPanel()
            } label: {
                Image(systemName: "sidebar.left")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Theme.textTertiary)
                    .frame(width: 26, height: 24)
                    .contentShape(Rectangle())
            }
            .buttonStyle(KeyButtonStyle())
            .help("Collapse panel")
        }
        .padding(.horizontal, 16)
        .frame(height: 50)
    }

    @ViewBuilder
    private var controls: some View {
        switch state.activeTool {
        case .padding:
            PaddingToolView(state: state)
        case .background:
            BackgroundToolView(state: state)
        default:
            EmptyView()
        }
    }
}
