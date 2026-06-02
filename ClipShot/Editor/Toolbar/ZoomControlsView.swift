import SwiftUI

/// Zoom cluster for the bottom status bar: zoom out / percentage dropdown / zoom in,
/// then the framing presets (fill selection, fit whole image, reset to center).
/// No floating chrome — it sits inside the status bar.
struct ZoomControlsView: View {
    @ObservedObject var zoom: CanvasZoomController

    var body: some View {
        HStack(spacing: 4) {
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

            IconButton(systemName: "viewfinder") { zoom.fitToSelection() }
                .help("Fill selected area")
                .accessibilityLabel("Fill selected area")

            IconButton(systemName: "arrow.up.left.and.down.right.magnifyingglass") {
                zoom.fitToCanvas()
            }
            .help("Fit whole image")
            .accessibilityLabel("Fit whole image")

            IconButton(systemName: "scope") { zoom.resetToCenter() }
                .help("Reset to center")
                .accessibilityLabel("Reset to center")
        }
    }

    private var separator: some View {
        Rectangle()
            .fill(Theme.hairline)
            .frame(width: 1, height: 16)
            .padding(.horizontal, 2)
    }

    private var percentMenu: some View {
        Menu {
            ForEach(zoom.presets, id: \.self) { preset in
                Button(ZoomMath.percentLabel(preset)) { zoom.setZoom(preset) }
            }
        } label: {
            Text(zoom.percentLabel)
                .font(Theme.mono(12, .semibold))
                .foregroundStyle(Theme.textPrimary)
                .frame(width: 48, height: 26)
                .contentShape(Rectangle())
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("Set zoom level")
        .accessibilityLabel("Zoom level")
    }
}
