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

private struct EditorShell: View {
    @StateObject private var state: EditorState
    @StateObject private var canvasFocusProxy = CanvasFocusProxy()
    @StateObject private var zoomController = CanvasZoomController()

    init(document: EditorDocument) {
        _state = StateObject(wrappedValue: EditorState(document: document, openingPanel: .canvas))
    }

    var body: some View {
        VStack(spacing: 0) {
            TopToolBarView(state: state)
            Rectangle().fill(Theme.hairline).frame(height: 1)
            HStack(spacing: 0) {
                ToolRailView(state: state)
                stage
                InspectorView(
                    state: state,
                    onCanvasFocusRequested: canvasFocusProxy.requestKeyboardFocus
                )
            }
            Rectangle().fill(Theme.hairline).frame(height: 1)
            statusBar
        }
        .frame(minWidth: 960, minHeight: 600)
        .background(Theme.surface)
    }

    /// The workbench: dot-grid backdrop, transparent canvas scroll view on top,
    /// registration ticks framing the corners.
    private var stage: some View {
        ZStack {
            StageBackdrop()
            CanvasView(state: state, focusProxy: canvasFocusProxy, zoomController: zoomController)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            StageCornerTicks()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// Instrument strip: live export dimensions on the left, zoom cluster on the right.
    private var statusBar: some View {
        HStack(spacing: 16) {
            HUDReadout(label: "PNG", value: exportSizeText)
            Spacer(minLength: 12)
            ZoomControlsView(zoom: zoomController)
        }
        .padding(.horizontal, 14)
        .frame(height: Theme.statusBarHeight)
        .frame(maxWidth: .infinity)
        .background(Theme.surface)
    }

    private var exportSizeText: String {
        let size = state.document.paddedDocumentSize
        return "\(Int(size.width.rounded())) × \(Int(size.height.rounded())) px"
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
        }
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
