import AppKit
import SwiftUI

struct EditorView: View {
    @ObservedObject var store: DOMCaptureSessionStore

    var body: some View {
        Group {
            if let session = store.session {
                EditorShell(document: EditorDocument(session: session))
                    // A new capture produces a new session id; .id() forces a fresh
                    // EditorShell (and fresh EditorState) so a second capture replaces
                    // the document instead of being ignored by @StateObject.
                    .id(session.id)
            } else {
                EmptyEditorView()
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
        ZStack {
            StageBackdrop()
            AmbientGlowView(colors: ambientColors)
            // Full bleed: the document and its background run underneath every
            // glass panel, so the chrome refracts the work itself.
            CanvasView(state: state, focusProxy: canvasFocusProxy, zoomController: zoomController)
        }
        .overlay(alignment: .topLeading) {
            TitleBarView(state: state)
                .padding(.leading, 78)
                .padding(.top, 10)
        }
        .overlay(alignment: .leading) {
            ToolRailView(state: state)
                .padding(.leading, Theme.chromeMargin)
        }
        .overlay(alignment: .trailing) {
            InspectorView(
                state: state,
                onCanvasFocusRequested: canvasFocusProxy.requestKeyboardFocus
            )
            .padding(.trailing, Theme.chromeMargin)
        }
        .ignoresSafeArea()
        .bottomDockBar {
            DockView(state: state, zoom: zoomController)
                .padding(.bottom, Theme.chromeMargin)
        }
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

private struct EmptyEditorView: View {
    var body: some View {
        ZStack {
            StageBackdrop()
            StageCornerTicks()
            VStack(spacing: 0) {
                Image(systemName: "viewfinder")
                    .font(.system(size: 30, weight: .regular))
                    .foregroundStyle(Theme.textTertiary)
                    .padding(.bottom, 18)
                Text("Nothing captured yet")
                    .font(Theme.title(15))
                    .foregroundStyle(Theme.textPrimary)
                    .padding(.bottom, 6)
                Text("Capture a component and it lands here, ready to frame.")
                    .font(Theme.label(12))
                    .foregroundStyle(Theme.textSecondary)
                    .padding(.bottom, 22)
                HStack(spacing: 5) {
                    Keycap(text: "⌃")
                    Keycap(text: "⇧")
                    Keycap(text: "5")
                    Text("in the browser, then pick a component")
                        .font(Theme.label(12))
                        .foregroundStyle(Theme.textTertiary)
                        .padding(.leading, 6)
                }
            }
            .padding(.horizontal, 44)
            .padding(.vertical, 40)
            .glassPanel(cornerRadius: 24)
        }
        .ignoresSafeArea()
        .frame(minWidth: 860, minHeight: 560)
    }
}

fileprivate extension EditorDocument {
    /// Bridge from the existing DOMCaptureSession into the new value-type document.
    init(session: DOMCaptureSession) {
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
            pageTitle: session.pageTitle,
            pageURL: session.pageURL,
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
