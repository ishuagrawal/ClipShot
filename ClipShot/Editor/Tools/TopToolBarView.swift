import SwiftUI

/// Slim top bar: Select plus the document-settings toggles on the left, page title on
/// the right. Drawing tools live in the floating `ToolPaletteView`, not here.
struct TopToolBarView: View {
    @ObservedObject var state: EditorState
    @Namespace private var indicator

    var body: some View {
        HStack(spacing: 4) {
            DocToggle(label: "Select", symbol: "cursorarrow",
                      isActive: state.documentPanel == .components, indicator: indicator) {
                state.toggleDocumentPanel(.components)
            }
            DocToggle(label: "Canvas", symbol: "photo.artframe",
                      isActive: state.documentPanel == .canvas, indicator: indicator) {
                state.toggleDocumentPanel(.canvas)
            }
            Spacer(minLength: 12)
            Text(state.document.pageTitle)
                .font(Theme.label(12))
                .foregroundStyle(Theme.textTertiary)
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .padding(.horizontal, 16)
        .frame(height: 48)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.surface)
        .animation(.spring(response: 0.30, dampingFraction: 0.82), value: state.documentPanel)
    }
}

private struct DocToggle: View {
    let label: String
    let symbol: String
    let isActive: Bool
    let indicator: Namespace.ID
    let onTap: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 7) {
                Image(systemName: symbol).font(.system(size: 12.5, weight: .medium))
                Text(label).font(Theme.label(12.5, isActive ? .semibold : .medium))
            }
            .foregroundStyle(isActive ? Theme.accentText : (hovering ? Theme.textPrimary : Theme.textSecondary))
            .padding(.horizontal, 12)
            .frame(height: 32)
            .background {
                if isActive {
                    RoundedRectangle(cornerRadius: Theme.radiusControl, style: .continuous)
                        .fill(Theme.accentDim)
                } else if hovering {
                    RoundedRectangle(cornerRadius: Theme.radiusControl, style: .continuous)
                        .fill(Theme.surfaceHover)
                }
            }
            .overlay(alignment: .bottom) {
                if isActive {
                    Capsule()
                        .fill(Theme.accent)
                        .frame(height: 2)
                        .padding(.horizontal, 8)
                        .offset(y: 7)
                        .matchedGeometryEffect(id: "doc-underline", in: indicator)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.12), value: hovering)
        .help(label)
        .accessibilityLabel(label)
        .accessibilityAddTraits(isActive ? [.isSelected] : [])
    }
}
