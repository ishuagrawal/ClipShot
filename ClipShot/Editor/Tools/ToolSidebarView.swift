import SwiftUI

/// Left inspector. Selection-driven: shows the selected annotation's controls, a pinned
/// document panel (Layout / Background), or a draw tool's defaults — whichever the current
/// `inspectorRoute` resolves to. The header title tracks that route.
struct ToolSidebarView: View {
    @ObservedObject var state: EditorState

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Rectangle().fill(Theme.hairline).frame(height: 1)
            ScrollView {
                content(for: state.inspectorRoute)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .frame(width: 284)
        .background(Theme.surface)
        .overlay(alignment: .trailing) {
            Rectangle().fill(Theme.hairline).frame(width: 1)
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Text(state.inspectorTitle)
                .font(Theme.title())
                .foregroundStyle(Theme.textPrimary)
            Spacer()
            IconButton(systemName: "xmark") { state.dismissInspector() }
                .help("Close panel")
                .accessibilityLabel("Close panel")
        }
        .padding(.horizontal, 18)
        .frame(height: 48)
    }

    @ViewBuilder
    private func content(for route: InspectorRoute) -> some View {
        switch route {
        case .hidden:
            // Excluded by isInspectorVisible (sidebar isn't rendered) — defensive only.
            EmptyView()
        case .layout:
            PaddingToolView(state: state)
        case .background:
            BackgroundToolView(state: state)
        case .annotation:
            SelectToolView(state: state)
        case .drawDefaults(let tool):
            switch tool {
            case .arrow:     ArrowToolView(state: state)
            case .rectangle: RectangleToolView(state: state)
            case .text:      TextToolView(state: state)
            default:         EmptyView()
            }
        }
    }
}
