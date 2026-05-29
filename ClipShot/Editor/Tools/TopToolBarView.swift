import SwiftUI

/// Top tool bar: horizontal tabs, one per tool that exposes a sidebar panel. Selecting a
/// tab activates the tool and swaps the left sidebar's controls. A teal indicator slides
/// under the active tab. Built to extend — annotation tools drop in as they ship.
struct TopToolBarView: View {
    @ObservedObject var state: EditorState
    @Namespace private var indicator

    /// Tools shown as tabs: those shipped *and* carrying a detail panel (Layout, Background).
    private var tabs: [EditorTool] {
        EditorTool.allCases.filter { $0.isEnabled && $0.hasDetailPanel }
    }

    var body: some View {
        HStack(spacing: 4) {
            ForEach(tabs) { tool in
                ToolTab(
                    tool: tool,
                    label: Self.tabLabel(tool),
                    isActive: state.activeTool == tool,
                    indicator: indicator
                ) {
                    state.selectTool(tool)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .frame(height: 50)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.surface)
        .animation(.spring(response: 0.30, dampingFraction: 0.82), value: state.activeTool)
    }

    /// Bar labels lean toward the editor verb rather than the model field name.
    static func tabLabel(_ tool: EditorTool) -> String {
        switch tool {
        case .padding:    return "Layout"
        case .background: return "Background"
        default:          return tool.displayName
        }
    }
}

private struct ToolTab: View {
    let tool: EditorTool
    let label: String
    let isActive: Bool
    let indicator: Namespace.ID
    let onTap: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 7) {
                Image(systemName: tool.symbolName)
                    .font(.system(size: 13, weight: .semibold))
                Text(label)
                    .font(Theme.label(12.5, isActive ? .semibold : .medium))
            }
            .foregroundStyle(
                isActive ? Theme.accentText
                : (hovering ? Theme.textPrimary : Theme.textSecondary)
            )
            .padding(.horizontal, 12)
            .frame(height: 34)
            .background {
                if isActive {
                    RoundedRectangle(cornerRadius: Theme.radiusSmall, style: .continuous)
                        .fill(Theme.accentDim)
                } else if hovering {
                    RoundedRectangle(cornerRadius: Theme.radiusSmall, style: .continuous)
                        .fill(Color.white.opacity(0.04))
                }
            }
            .overlay(alignment: .bottom) {
                if isActive {
                    Capsule()
                        .fill(Theme.accent)
                        .frame(height: 2)
                        .padding(.horizontal, 6)
                        .offset(y: 8)
                        .shadow(color: Theme.accentGlow, radius: 4)
                        .matchedGeometryEffect(id: "tab-underline", in: indicator)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.12), value: hovering)
        .accessibilityLabel(label)
        .accessibilityAddTraits(isActive ? [.isSelected] : [])
        .help(label)
    }
}
