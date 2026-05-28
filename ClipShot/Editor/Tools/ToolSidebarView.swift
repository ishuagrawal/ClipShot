import SwiftUI

/// Left sidebar: fixed icon rail plus an expanding detail panel for tool controls.
struct ToolSidebarView: View {
    @ObservedObject var state: EditorState

    var body: some View {
        HStack(spacing: 0) {
            rail
            if state.isDetailPanelVisible {
                Rectangle()
                    .fill(Color.white.opacity(0.06))
                    .frame(width: 1)
                detailPanel
                    .frame(width: 240)
                    .transition(.move(edge: .leading).combined(with: .opacity))
            }
        }
        .animation(.easeInOut(duration: 0.18), value: state.isDetailPanelVisible)
        .animation(.easeInOut(duration: 0.18), value: state.activeTool)
    }

    private var rail: some View {
        VStack(spacing: 10) {
            ForEach(EditorTool.allCases) { tool in
                ToolButton(tool: tool, state: state) {
                    state.selectTool(tool)
                }
            }
            Spacer()
            Button {
                state.toggleDetailPanel()
            } label: {
                Image(systemName: state.isDetailPanelVisible ? "sidebar.left" : "sidebar.right")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(Color.white.opacity(0.4))
                    .frame(width: 38, height: 38)
            }
            .buttonStyle(.plain)
            .keyboardShortcut("i", modifiers: [.command])
            .disabled(!state.activeTool.hasDetailPanel)
            .help("Toggle panel (Command-I)")
        }
        .padding(.top, 18)
        .padding(.horizontal, 6)
        .padding(.bottom, 12)
        .frame(width: 54)
        .background(Color.black.opacity(0.25))
    }

    @ViewBuilder
    private var detailPanel: some View {
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

private struct ToolButton: View {
    let tool: EditorTool
    @ObservedObject var state: EditorState
    let onTap: () -> Void

    var body: some View {
        let isActive = state.activeTool == tool
        let isEnabled = tool.isEnabled

        Button(action: onTap) {
            Image(systemName: tool.symbolName)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(
                    isActive ? Color.white
                    : (isEnabled ? Color.white.opacity(0.66) : Color.white.opacity(0.22))
                )
                .frame(width: 38, height: 38)
                .background {
                    if isActive {
                        RoundedRectangle(cornerRadius: 9, style: .continuous)
                            .fill(Color.blue)
                            .shadow(color: .blue.opacity(0.35), radius: 10, y: 3)
                    }
                }
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .accessibilityLabel(tool.displayName)
        .help(isEnabled ? tool.displayName : "\(tool.displayName) - \(tool.comingSoonNote)")
    }
}
