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
        _state = StateObject(wrappedValue: EditorState(document: document, openingPanel: .layout))
    }

    var body: some View {
        VStack(spacing: 0) {
            TopToolBarView(state: state)
            Rectangle().fill(Theme.hairline).frame(height: 1)
            HStack(spacing: 0) {
                if state.isInspectorVisible {
                    ToolSidebarView(
                        state: state,
                        onCanvasFocusRequested: canvasFocusProxy.requestKeyboardFocus
                    )
                }
                canvasArea
            }
            Rectangle().fill(Theme.hairline).frame(height: 1)
            statusBar
        }
        .frame(minWidth: 900, minHeight: 600)
        .background(Theme.canvas)
    }

    private var statusBar: some View {
        HStack(spacing: 0) {
            Spacer(minLength: 12)
            ZoomControlsView(zoom: zoomController)
        }
        .padding(.horizontal, 12)
        .frame(height: 36)
        .frame(maxWidth: .infinity)
        .background(Theme.surface)
    }

    private var canvasArea: some View {
        ZStack {
            CanvasView(state: state, focusProxy: canvasFocusProxy, zoomController: zoomController)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Theme.canvas)
            VStack {
                ToolPaletteView(state: state)
                    .padding(.top, 14)
                Spacer()
            }
            VStack {
                Spacer()
                BottomBarView(state: state)
                    .padding(.bottom, 20)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

}

private struct EmptyEditorView: View {
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "crop")
                .font(.system(size: 34, weight: .medium))
                .foregroundStyle(Theme.textTertiary)
            Text("No capture session")
                .font(Theme.title(16))
                .foregroundStyle(Theme.textSecondary)
        }
        .frame(minWidth: 860, minHeight: 560)
        .background(Theme.canvas)
    }
}

fileprivate extension EditorDocument {
    /// Bridge from the existing DOMCaptureSession into the new value-type document.
    init(session: DOMCaptureSession) {
        let pixelSelection = session.pixelRect(for: session.selectedRect)
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
            padding: .zero,
            background: .none,
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
