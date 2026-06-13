import SwiftUI

/// Menu bar popover: capture entry point and quit, styled on a glassy material
/// so the brand starts at the menu bar.
struct MenuContentView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
                .padding(.horizontal, 16)
                .padding(.top, 14)
                .padding(.bottom, 12)

            Rectangle().fill(Theme.hairline).frame(height: 1)

            MenuRowButton {
                appState.onOpenHome?()
            } label: {
                Text("Open ClipShot")
                    .font(Theme.label(12.5, .semibold))
                    .foregroundStyle(Theme.textPrimary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(6)

            Rectangle().fill(Theme.hairline).frame(height: 1)

            MenuRowButton {
                appState.onBeginCapture?()
            } label: {
                captureRow(
                    title: "Screen capture",
                    detail: "Drag an exact region or click a window.",
                    keys: ["⌃", "⇧", "5"]
                )
            }
            .padding(6)

            Rectangle().fill(Theme.hairline).frame(height: 1)

            MenuRowButton {
                NSApplication.shared.terminate(nil)
            } label: {
                Text("Quit ClipShot")
                    .font(Theme.label(11.5))
                    .foregroundStyle(Theme.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(6)
        }
        .frame(width: 320)
        .background(.ultraThinMaterial)
        .preferredColorScheme(.dark)
    }

    private var header: some View {
        HStack(spacing: 8) {
            BrandMarkGlyph()
                .frame(width: 28, height: 28)
            Text("ClipShot")
                .font(Theme.title(14))
                .foregroundStyle(Theme.textPrimary)
            Spacer()
        }
    }

    private func captureRow(title: String, detail: String, keys: [String]) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 4) {
                Text(title)
                    .font(Theme.label(12.5, .semibold))
                    .foregroundStyle(Theme.textPrimary)
                Spacer(minLength: 10)
                ForEach(keys, id: \.self) { key in
                    Keycap(text: key)
                }
            }
            Text(detail)
                .font(Theme.label(11.5))
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
    }
}

/// Menu row that highlights on hover like a native macOS menu item.
private struct MenuRowButton<Label: View>: View {
    let action: () -> Void
    @ViewBuilder let label: () -> Label
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            label()
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        }
        .buttonStyle(.plain)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(Color.primary.opacity(isHovered ? 0.08 : 0))
        )
        .onHover { isHovered = $0 }
    }
}
