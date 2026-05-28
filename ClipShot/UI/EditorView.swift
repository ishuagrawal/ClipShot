import AppKit
import SwiftUI

struct EditorView: View {
    @ObservedObject var store: DOMCaptureSessionStore

    var body: some View {
        Group {
            if let session = store.session {
                EditorShell(state: EditorState(document: EditorDocument(session: session)))
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
    @StateObject var state: EditorState

    var body: some View {
        ZStack(alignment: .bottom) {
            HStack(spacing: 0) {
                ToolSidebarView(state: state)
                Divider().background(Color.white.opacity(0.06))
                CanvasView(state: state)
                    .background(Color(red: 0.025, green: 0.027, blue: 0.032))
            }

            BottomBarView(state: state)
                .padding(.bottom, 20)
        }
        .frame(minWidth: 900, minHeight: 600)
        .background(Color(red: 0.055, green: 0.057, blue: 0.06))
    }
}

private struct EmptyEditorView: View {
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "crop")
                .font(.system(size: 34, weight: .medium))
                .foregroundStyle(.secondary)
            Text("No capture session")
                .font(.headline)
        }
        .frame(minWidth: 860, minHeight: 560)
        .background(Color(red: 0.055, green: 0.057, blue: 0.06))
        .foregroundStyle(.secondary)
    }
}

extension EditorDocument {
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
