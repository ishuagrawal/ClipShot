import SwiftUI

/// Select-mode inspector: lists every annotation on the canvas, top-most first. Tapping a
/// row selects that annotation, which routes the inspector to its detail editor.
struct ComponentListView: View {
    @ObservedObject var state: EditorState
    var onCanvasFocusRequested: () -> Void = {}

    var body: some View {
        if state.document.annotations.isEmpty {
            emptyState
        } else {
            VStack(alignment: .leading, spacing: 2) {
                // Top-most annotation first, matching canvas hit-test order.
                ForEach(Array(state.document.annotations.enumerated().reversed()), id: \.element.id) { _, annotation in
                    ComponentRow(
                        annotation: annotation,
                        isSelected: state.selectedAnnotationID == annotation.id
                    ) {
                        state.selectComponent(annotation.id)
                        onCanvasFocusRequested()
                    }
                }
            }
        }
    }

    private var emptyState: some View {
        Text("Draw with the tools below to add arrows, boxes, or text.")
            .font(Theme.label(11.5))
            .foregroundStyle(Theme.textTertiary)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct ComponentRow: View {
    let annotation: Annotation
    let isSelected: Bool
    var action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: annotation.kind.symbolName)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(isSelected ? Theme.accentText : Theme.textSecondary)
                    .frame(width: 18)
                Text(annotation.kind.listLabel)
                    .font(Theme.label(12.5))
                    .foregroundStyle(isSelected ? Theme.accentText : Theme.textPrimary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10)
            .frame(height: 34)
            .background(
                RoundedRectangle(cornerRadius: Theme.radiusControl, style: .continuous)
                    .fill(isSelected ? Theme.accentDim : (hovering ? Theme.surfaceHover : .clear))
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.1), value: hovering)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }
}

private extension Annotation.Kind {
    var symbolName: String {
        switch self {
        case .arrow(_, _, let pathStyle, _, _, _, _):
            return pathStyle == .straight ? "arrow.up.right" : "arrow.uturn.up"
        case .line:  return "line.diagonal"
        case .rect:  return "rectangle"
        case .text:  return "textformat"
        case .blur:  return "drop.halffull"
        }
    }

    var listLabel: String {
        switch self {
        case .arrow(_, _, let pathStyle, _, _, _, _):
            return pathStyle.displayName
        case .line:  return "Line"
        case .rect:  return "Rectangle"
        case .blur:  return "Blur"
        case .text(_, let string, _, _):
            let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? "Text" : trimmed
        }
    }
}
