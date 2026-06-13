import AppKit
import SwiftUI

struct EditorView: View {
    @ObservedObject var store: CaptureSessionStore
    /// Reopens a recents entry as a fresh session; consumed by the home page (Task 3).
    var onReopenRecent: (RecentEntry) -> Void = { _ in }

    var body: some View {
        Group {
            if let session = store.session {
                EditorShell(document: EditorDocument(session: session))
                    // A new capture produces a new session id; .id() forces a fresh
                    // EditorShell (and fresh EditorState) so a second capture replaces
                    // the document instead of being ignored by @StateObject.
                    .id(session.id)
            } else {
                HomeView(onReopenRecent: onReopenRecent)
            }
        }
        .preferredColorScheme(.dark)
    }
}

/// One full-bleed stage; every piece of chrome floats over it as Liquid Glass.
/// Three anchors only: identity top-left, properties down the right, and one
/// dock along the bottom holding history, tools, and zoom. The capture's own
/// palette bleeds across the stage underneath, so the glass refracts its colors.
private struct EditorShell: View {
    @StateObject private var state: EditorState
    @StateObject private var canvasFocusProxy = CanvasFocusProxy()
    @StateObject private var zoomController = CanvasZoomController()
    /// Mesh palette is derived from the (immutable) screenshot once, not per render.
    @State private var meshPalette: [Color] = []

    init(document: EditorDocument) {
        _state = StateObject(wrappedValue: EditorState(document: document, openingPanel: .canvas))
    }

    var body: some View {
        // The inspector scales with the window (roughly proportional), and the
        // canvas fit, dock centering, and export-pod alignment all measure
        // against it — so derive one live width here and thread it through.
        GeometryReader { geo in
            let inspectorWidth = Theme.inspectorWidth(forWindowWidth: geo.size.width)
            let rightChrome = Theme.rightChromeWidth(forInspector: inspectorWidth)
            ZStack {
                StageBackdrop()
                AmbientGlowView(colors: ambientColors)
                // Full bleed: the document and its background run underneath every
                // glass panel, so the chrome refracts the work itself.
                CanvasView(
                    state: state,
                    focusProxy: canvasFocusProxy,
                    zoomController: zoomController,
                    rightOcclusion: rightChrome
                )
            }
            // Mirror of the inspector's scroll fade for the canvas itself: when
            // the image is panned up under the top chrome it blurs and dissolves
            // across the same band instead of sliding hard-edged behind the bar.
            // Solid through the chrome, fading out exactly at the image's rest
            // position (top chrome + fit margin), so it is invisible until the
            // image actually moves under it.
            .overlay(alignment: .top) {
                let bandHeight = Theme.topChromeHeight + Theme.canvasFitMargin
                let fadeStart = (bandHeight - Theme.scrollFadeBand) / bandHeight
                Rectangle()
                    .fill(.ultraThinMaterial)
                    .background(Theme.canvas.opacity(0.55))
                    .frame(height: bandHeight)
                    .mask(
                        LinearGradient(stops: [
                            .init(color: .black, location: 0),
                            .init(color: .black, location: fadeStart),
                            .init(color: .black.opacity(0), location: 1)
                        ], startPoint: .top, endPoint: .bottom)
                    )
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
            .overlay(alignment: .trailing) {
                InspectorView(
                    state: state,
                    onCanvasFocusRequested: canvasFocusProxy.requestKeyboardFocus
                )
                // Cards live in the zone between the control bar and the dock. The
                // frame reaches a fade-overhang above the chrome line so the full
                // fade band fits while ending opaque exactly at the image top.
                .padding(.top, Theme.topChromeHeight - Theme.scrollFadeOverhang)
                .padding(.trailing, Theme.chromeMargin)
            }
            .overlay(alignment: .top) {
                VStack(spacing: Theme.chromeMargin) {
                    titleStrip
                    // The export pod's right edge lines up with the image's right
                    // edge (the inspector column plus the canvas fit margin); the
                    // title plate keeps the window-margin alignment on the left.
                    TitleBarView(state: state)
                        .padding(.leading, Theme.chromeMargin + Theme.panelInset)
                        .padding(.trailing, exportPodTrailingPadding(
                            windowSize: geo.size,
                            rightChrome: rightChrome
                        ))
                }
            }
            // Stage and overlays bleed under the titlebar and the dock bar; the
            // dock's safeAreaBar would otherwise carve a dead strip out of the
            // backdrop along the bottom.
            .ignoresSafeArea()
            .bottomDockBar {
                DockView(state: state, zoom: zoomController)
                    // Center the dock in the clear space the image occupies, not
                    // the full window: shift left by the right chrome's width.
                    .padding(.trailing, rightChrome)
                    .padding(.bottom, Theme.chromeMargin)
            }
            .environment(\.inspectorWidth, inspectorWidth)
        }
        .ignoresSafeArea()
        .frame(minWidth: 980, minHeight: 620)
        .onAppear {
            meshPalette = MeshGradientGenerator
                .generate(screenshot: state.document.screenshot,
                          selection: state.document.baseSelection)
                .colors
                .map { Color(cgColor: $0) }
            // SwiftUI hands initial key focus to the first text field (the title),
            // which selects its text and steals canvas shortcuts. Canvas wins.
            DispatchQueue.main.async {
                canvasFocusProxy.requestKeyboardFocus()
            }
        }
    }

    /// Trailing padding that puts the export pod's right edge on the image's
    /// right edge at the initial fit. Mirrors the canvas fit: the image scales
    /// to fill the clear space (window minus chrome occlusions) inside the fit
    /// margin, centered — so when the image is height-constrained its right
    /// edge sits further in than the clear-space edge.
    private func exportPodTrailingPadding(windowSize: CGSize, rightChrome: CGFloat) -> CGFloat {
        let crop = CanvasCoordinator.initialFocusBounds(
            focus: state.document.fitFocusRect,
            imageBounds: state.document.imageBounds
        )
        let clearWidth = windowSize.width - rightChrome
        let clearHeight = windowSize.height - Theme.topChromeHeight - Theme.bottomChromeHeight
        let margin = Theme.canvasFitMargin
        guard crop.width > 0, crop.height > 0,
              clearWidth > margin * 2, clearHeight > margin * 2 else {
            return rightChrome + margin
        }
        let scale = min((clearWidth - margin * 2) / crop.width,
                        (clearHeight - margin * 2) / crop.height)
        let displayedWidth = crop.width * scale
        return rightChrome + (clearWidth - displayedWidth) / 2
    }

    /// Hand-drawn titlebar: the app name centered on the stoplight row. The system
    /// title is hidden because this OS lays it beside the stoplights instead.
    private var titleStrip: some View {
        Text("ClipShot")
            .font(Theme.title(13))
            .foregroundStyle(Theme.textSecondary)
            .frame(maxWidth: .infinity)
            .frame(height: Theme.titleStripHeight)
            .background(Color.black.opacity(0.22))
            .overlay(alignment: .bottom) {
                Rectangle()
                    .fill(Theme.hairline)
                    .frame(height: 1)
            }
    }

    /// The capture decides the room's light. Dynamic/none backgrounds diffuse the
    /// screenshot's harmonized mesh palette; explicit backgrounds diffuse themselves.
    private var ambientColors: [Color] {
        switch state.document.background {
        case .solidColor(let color):
            return [Color(cgColor: color)]
        case .gradient(let start, let end, _):
            return [Color(cgColor: start), Color(cgColor: end),
                    Color(cgColor: start), Color(cgColor: end),
                    Color(cgColor: start).opacity(0.8), Color(cgColor: end)]
        case .dynamic, .none:
            return meshPalette
        }
    }
}

fileprivate extension EditorDocument {
    /// Bridge from a CaptureSession into the value-type document.
    init(session: CaptureSession) {
        let pixelSelection = session.pixelRect(for: session.selectedRect)
        let selectionRadii = session.pixelCornerRadii(for: session.selectedBorderRadii)
        let premaskedRadii = session.pixelCornerRadii(for: session.premaskedCornerRadii)
        self.init(
            screenshot: NSBitmapImageRep(data: session.screenshotData)?.cgImage
                ?? CGImage.makeOnePixelTransparent(),
            viewport: CGSize(
                width: CGFloat(session.viewport.width),
                height: CGFloat(session.viewport.height)
            ),
            sourceTitle: session.sourceTitle,
            sourceURL: session.sourceURL,
            baseSelection: pixelSelection,
            selectionCornerRadii: selectionRadii,
            contentCornerRadii: selectionRadii.isZero ? premaskedRadii : selectionRadii,
            padding: PaddingConfig.autoSweetSpot(forSelection: pixelSelection.size),
            background: .dynamic,
            annotations: []
        )
    }
}

private extension CGImage {
    /// Defensive fallback if the screenshot data cannot be re-decoded — keeps the editor
    /// from crashing while still surfacing a visibly broken (1-pixel) image.
    static func makeOnePixelTransparent() -> CGImage {
        let cs = CGColorSpace(name: CGColorSpace.sRGB)!
        let ctx = CGContext(
            data: nil, width: 1, height: 1, bitsPerComponent: 8,
            bytesPerRow: 4, space: cs,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
                | CGBitmapInfo.byteOrder32Big.rawValue
        )!
        return ctx.makeImage()!
    }
}
