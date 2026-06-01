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

    init(document: EditorDocument) {
        _state = StateObject(wrappedValue: EditorState(document: document, openingPanel: .layout))
    }

    var body: some View {
        ZStack {
            VStack(spacing: 0) {
                TopToolBarView(state: state)
                Rectangle().fill(Theme.hairline).frame(height: 1)
                HStack(spacing: 0) {
                    if state.isInspectorVisible {
                        ToolSidebarView(state: state)
                    }
                    canvasArea
                }
            }
            panelToggleShortcut
            toolShortcuts
        }
        .frame(minWidth: 900, minHeight: 600)
        .background(Theme.canvas)
    }

    private var canvasArea: some View {
        ZStack {
            CanvasView(state: state)
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

    private var panelToggleShortcut: some View {
        Button {
            // ⌘I closes whatever the inspector is showing, or opens Layout if it's hidden.
            if state.isInspectorVisible {
                state.dismissInspector()
            } else {
                state.toggleDocumentPanel(.layout)
            }
        } label: {
            Color.clear.frame(width: 0, height: 0)
        }
        .buttonStyle(.plain)
        .keyboardShortcut("i", modifiers: [.command])
        .accessibilityHidden(true)
    }

    /// Single-key tool shortcuts (no modifier). Draw tools via the palette; Select / Layout /
    /// Background toggle their inspector panels — mirrors the original V/P/B/A/R/T map.
    private var toolShortcuts: some View {
        ZStack {
            panelKey("v", .components)
            cursorKey("a", .arrow)
            cursorKey("r", .rectangle)
            cursorKey("t", .text)
            panelKey("p", .layout)
            panelKey("b", .background)
        }
        .accessibilityHidden(true)
    }

    private func cursorKey(_ key: KeyEquivalent, _ tool: EditorTool) -> some View {
        Button { state.selectCursorTool(tool) } label: { Color.clear.frame(width: 0, height: 0) }
            .buttonStyle(.plain)
            .keyboardShortcut(key, modifiers: [])
    }

    private func panelKey(_ key: KeyEquivalent, _ panel: DocumentPanel) -> some View {
        Button { state.toggleDocumentPanel(panel) } label: { Color.clear.frame(width: 0, height: 0) }
            .buttonStyle(.plain)
            .keyboardShortcut(key, modifiers: [])
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
