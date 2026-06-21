import AppKit
import SwiftUI

struct EditorView: View {
    @ObservedObject var store: CaptureSessionStore
    /// Reopens a recents entry as a fresh session; consumed by the home page (Task 3).
    var onReopenRecent: (RecentEntry) -> Void = { _ in }
    /// Import an opened/dropped image as a new session; false means unreadable.
    var onImportFile: (URL) async -> Bool = { _ in false }
    var onImportData: (Data, String) async -> Bool = { _, _ in false }

    var body: some View {
        Group {
            if let session = store.session {
                // Clearing the session flips this Group back to HomeView in the
                // same window; the capture stays in recents (recorded on open).
                EditorShell(document: EditorDocument(session: session),
                            onGoHome: { store.session = nil })
                    // A new capture produces a new session id; .id() forces a fresh
                    // EditorShell (and fresh EditorState) so a second capture replaces
                    // the document instead of being ignored by @StateObject.
                    .id(session.id)
            } else {
                HomeView(onReopenRecent: onReopenRecent,
                         onImportFile: onImportFile,
                         onImportData: onImportData)
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
    /// Edge palette sampled from the rendered background (wallpaper or gradient),
    /// the same pixel-sampling path so every background lights the room identically.
    @State private var samplePalette: [Color] = []
    @State private var samplePaletteKey = ""
    private let onGoHome: () -> Void

    init(document: EditorDocument, onGoHome: @escaping () -> Void = {}) {
        _state = StateObject(wrappedValue: EditorState(document: document, openingPanel: .canvas))
        self.onGoHome = onGoHome
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
                AmbientGlowView(colors: ambientColors, cardFrame: zoomController.cardFrame)
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
                    // The export pod pins to the clear-space right edge so it stays
                    // put when the screenshot resizes; the title plate keeps the
                    // window-margin alignment on the left.
                    TitleBarView(state: state, onGoHome: onGoHome)
                        .padding(.leading, Theme.chromeMargin + Theme.panelInset)
                        .padding(.trailing, rightChrome + Theme.canvasFitMargin)
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
            recomputeBackgroundPalette()
            // SwiftUI hands initial key focus to the first text field (the title),
            // which selects its text and steals canvas shortcuts. Canvas wins.
            DispatchQueue.main.async {
                canvasFocusProxy.requestKeyboardFocus()
            }
        }
        .onChange(of: state.document.background) { _, _ in
            recomputeBackgroundPalette()
        }
        .onChange(of: state.document.effectiveCrop) { _, _ in
            recomputeBackgroundPalette()
        }
        .onChange(of: state.previewingOriginal) { _, _ in
            recomputeBackgroundPalette()
        }
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
        switch state.displayDocument.background {
        case .solidColor(let color):
            return [Color(cgColor: color)]
        case .gradient(let start, let end, let angle):
            // Exact, not sampled: evaluate the gradient at the 9 anchor points with
            // the same projection CAGradientLayer uses. No rasterization/flip risk.
            return Self.gradientGrid(start: start, end: end, angle: angle,
                                     size: state.displayDocument.effectiveCrop.size)
                .map { Color(cgColor: $0) }
        case .image:
            return samplePalette.isEmpty ? meshPalette : samplePalette
        case .dynamic, .none:
            return meshPalette
        }
    }

    /// The linear gradient evaluated at the 9 blob anchors (mesh order, v top-down:
    /// index 0 = top-left, 8 = bottom-right), via the exact axis projection the live
    /// CAGradientLayer uses. Same anchor layout as `EdgePaletteSampler`.
    private static func gradientGrid(start: CGColor, end: CGColor,
                                     angle: CGFloat, size: CGSize) -> [CGColor] {
        let w = max(1, size.width), h = max(1, size.height)
        let rad = angle * .pi / 180
        let half = max(w, h) / 2
        // Matches both the live CAGradientLayer and the export renderer: their
        // start/end pixels are identical (center − dir·max(w,h)/2), start top-right
        // at 135°. Evaluated in this same top-left-origin unit space.
        let dx = cos(rad) * half, dy = sin(rad) * half
        let s = CGPoint(x: 0.5 - dx / w, y: 0.5 - dy / h)
        let e = CGPoint(x: 0.5 + dx / w, y: 0.5 + dy / h)
        let ax = e.x - s.x, ay = e.y - s.y
        let len2 = ax * ax + ay * ay
        let zones: [CGFloat] = [0, 0.5, 1]
        var grid: [CGColor] = []
        for v in zones {
            for u in zones {
                let t = len2 > 0
                    ? min(1, max(0, ((u - s.x) * ax + (v - s.y) * ay) / len2))
                    : 0.5
                grid.append(lerp(start, end, t))
            }
        }
        return grid
    }

    private static func lerp(_ a: CGColor, _ b: CGColor, _ t: CGFloat) -> CGColor {
        let ca = a.components ?? [0, 0, 0, 1], cb = b.components ?? [0, 0, 0, 1]
        guard ca.count >= 3, cb.count >= 3 else { return a }
        return CGColor(srgbRed: ca[0] + (cb[0] - ca[0]) * t,
                       green: ca[1] + (cb[1] - ca[1]) * t,
                       blue: ca[2] + (cb[2] - ca[2]) * t, alpha: 1)
    }

    /// Wallpapers can't be computed in closed form, so decode the image and sample
    /// its 9 edge zones via `EdgePaletteSampler`. Gradients are evaluated exactly in
    /// `ambientColors`; other backgrounds need no palette here.
    private func recomputeBackgroundPalette() {
        let document = state.displayDocument
        guard let request = BackgroundPaletteRequest(
            background: document.background,
            effectiveCrop: document.effectiveCrop
        ) else {
            samplePalette = []
            samplePaletteKey = ""
            return
        }

        guard samplePaletteKey != request.key else { return }
        samplePaletteKey = request.key
        // Keep the previous palette visible until the new sample lands — clearing it
        // here makes the glow flash to the mesh fallback during a padding drag.

        switch document.background {
        case .image(let ref):
            Task.detached(priority: .userInitiated) {
                guard let image = WallpaperImageCache.shared.thumbnail(for: ref, maxPixel: 256)
                    ?? WallpaperImageCache.shared.image(for: ref) else { return }
                let colors = EdgePaletteSampler.grid(from: image, cardAspect: request.aspect)
                    .map { Color(cgColor: $0) }
                await MainActor.run {
                    guard request.matches(
                        background: state.displayDocument.background,
                        effectiveCrop: state.displayDocument.effectiveCrop,
                        currentKey: samplePaletteKey
                    ) else {
                        return
                    }
                    samplePalette = colors
                }
            }
        default:
            break
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
