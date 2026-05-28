import SwiftUI

struct ToolSidebarView: View {
    @ObservedObject var state: EditorState

    var body: some View {
        VStack(spacing: 10) {
            ForEach(EditorTool.allCases) { tool in
                ToolButton(tool: tool, state: state)
            }
            Spacer()
        }
        .padding(.top, 18)
        .padding(.horizontal, 6)
        .frame(width: 54)
        .background(Color.black.opacity(0.25))
    }
}

private struct ToolButton: View {
    let tool: EditorTool
    @ObservedObject var state: EditorState

    var body: some View {
        let isActive = state.activeTool == tool
        let isEnabled = tool.isEnabledInP0

        Button {
            guard isEnabled else { return }
            state.activeTool = tool
        } label: {
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
    }
}
