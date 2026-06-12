import SwiftUI

/// Zoom cluster for the bottom status bar: zoom out / percentage dropdown / zoom in,
/// then a single framing action that restores the initial-load view.
/// No floating chrome — it sits inside the status bar like an instrument readout.
struct ZoomControlsView: View {
    @ObservedObject var zoom: CanvasZoomController

    var body: some View {
        HStack(spacing: 2) {
            IconButton(systemName: "minus") { zoom.zoomOut() }
                .help("Zoom out")
                .accessibilityLabel("Zoom out")
                .disabled(!zoom.canZoomOut)
                .opacity(zoom.canZoomOut ? 1 : 0.35)

            percentMenu

            IconButton(systemName: "plus") { zoom.zoomIn() }
                .help("Zoom in")
                .accessibilityLabel("Zoom in")
                .disabled(!zoom.canZoomIn)
                .opacity(zoom.canZoomIn ? 1 : 0.35)

            separator

            IconButton(systemName: "scope") { zoom.resetToCenter() }
                .help("Reset view")
                .accessibilityLabel("Reset view")
        }
    }

    private var separator: some View {
        Rectangle()
            .fill(Theme.hairline)
            .frame(width: 1, height: 14)
            .padding(.horizontal, 6)
    }

    private var percentMenu: some View {
        Menu {
            ForEach(zoom.presets, id: \.self) { preset in
                Button(ZoomMath.percentLabel(preset)) { zoom.setZoom(preset) }
            }
        } label: {
            Text(zoom.percentLabel)
                .font(Theme.mono(11.5, .semibold))
                .foregroundStyle(Theme.textSecondary)
                .frame(width: 48, height: 24)
                .contentShape(Rectangle())
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("Set zoom level")
        .accessibilityLabel("Zoom level")
    }
}
