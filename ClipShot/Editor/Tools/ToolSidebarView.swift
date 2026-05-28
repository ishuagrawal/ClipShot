import SwiftUI

struct ToolSidebarView: View {
    @ObservedObject var state: EditorState
    @State private var presentedTool: EditorTool?

    var body: some View {
        VStack(spacing: 10) {
            ForEach(EditorTool.allCases) { tool in
                ToolButton(
                    tool: tool,
                    state: state,
                    isPopoverPresented: Binding(
                        get: { presentedTool == tool },
                        set: { presentedTool = $0 ? tool : nil }
                    ),
                    onTap: { handleTap(tool) }
                )
            }
            Spacer()
        }
        .padding(.top, 18)
        .padding(.horizontal, 6)
        .frame(width: 54)
        .background(Color.black.opacity(0.25))
    }

    private func handleTap(_ tool: EditorTool) {
        guard tool.isEnabled else { return }
        state.activeTool = tool
        switch tool {
        case .padding, .background:
            presentedTool = presentedTool == tool ? nil : tool
        default:
            presentedTool = nil
        }
    }
}

private struct ToolButton: View {
    let tool: EditorTool
    @ObservedObject var state: EditorState
    @Binding var isPopoverPresented: Bool
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
        .help(isEnabled ? tool.displayName : "\(tool.displayName) — \(tool.comingSoonNote)")
        .popover(isPresented: $isPopoverPresented, arrowEdge: .leading) {
            popoverContent
        }
    }

    @ViewBuilder
    private var popoverContent: some View {
        switch tool {
        case .padding:
            PaddingToolView(state: state)
        case .background:
            BackgroundToolView(state: state)
        default:
            EmptyView()
        }
    }
}
