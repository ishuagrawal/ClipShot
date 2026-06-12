import SwiftUI

/// Menu bar popover: capture entry points, bridge status, quit. Styled as a small
/// slab of the editor's drafting-room chrome so the brand starts at the menu bar.
struct MenuContentView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
                .padding(.horizontal, 16)
                .padding(.top, 14)
                .padding(.bottom, 12)

            Rectangle().fill(Theme.hairline).frame(height: 1)

            VStack(alignment: .leading, spacing: 14) {
                captureRow(
                    title: "Screen capture",
                    detail: "Drag an exact region or click a window.",
                    keys: ["⌃", "⇧", "5"]
                )
                captureRow(
                    title: "Web component capture",
                    detail: "Same shortcut inside Arc or Chrome picks a DOM component and opens it here.",
                    keys: ["⌃", "⇧", "5"]
                )
            }
            .padding(16)

            Rectangle().fill(Theme.hairline).frame(height: 1)

            HStack(spacing: 8) {
                Circle()
                    .fill(appState.lastCaptureStatus != nil ? Theme.accent : Theme.textTertiary)
                    .frame(width: 6, height: 6)
                Text(appState.lastCaptureStatus ?? "Starting DOM bridge")
                    .font(Theme.label(11))
                    .foregroundStyle(Theme.textSecondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Spacer(minLength: 12)
                Button("Quit ClipShot") {
                    NSApplication.shared.terminate(nil)
                }
                .buttonStyle(.plain)
                .font(Theme.label(11.5))
                .foregroundStyle(Theme.textSecondary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 11)
        }
        .frame(width: 320)
        .background(Theme.surface)
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
