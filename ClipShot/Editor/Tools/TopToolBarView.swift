import SwiftUI

/// Floating identity chip, top left beside the traffic lights: the brand tick
/// and the capture's editable title. The title doubles as the export filename;
/// everything command-like lives in the dock.
struct TitleBarView: View {
    @ObservedObject var state: EditorState
    @FocusState private var titleFocused: Bool

    var body: some View {
        HStack(spacing: 9) {
            BrandTickGlyph()
                .frame(width: 12, height: 12)
            Text("ClipShot")
                .font(Theme.title(12.5))
                .foregroundStyle(Theme.textPrimary)
            Rectangle()
                .fill(Theme.hairlineStrong)
                .frame(width: 1, height: 13)
            titleField
        }
        .padding(.horizontal, 14)
        .frame(height: 36)
        .glassPanel(cornerRadius: 18)
    }

    private var titleField: some View {
        TextField(
            "Untitled capture",
            text: Binding(
                get: { state.document.pageTitle },
                set: { state.document.pageTitle = $0 }
            )
        )
        .textFieldStyle(.plain)
        .font(Theme.label(12))
        .foregroundStyle(titleFocused ? Theme.textPrimary : Theme.textSecondary)
        .focused($titleFocused)
        .onSubmit { titleFocused = false }
        .frame(width: 230)
        .help("Capture title — used as the export filename")
        .accessibilityLabel("Capture title")
    }
}
