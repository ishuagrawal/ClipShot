import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct BottomBarView: View {
    @ObservedObject var state: EditorState

    var body: some View {
        HStack(spacing: 6) {
            BarIconButton(systemName: "arrow.uturn.backward") { state.performUndo() }
                .accessibilityLabel("Undo")
                .disabled(!state.undoStack.canUndo)
                .opacity(state.undoStack.canUndo ? 1 : 0.35)

            BarIconButton(systemName: "arrow.uturn.forward") { state.performRedo() }
                .accessibilityLabel("Redo")
                .disabled(!state.undoStack.canRedo)
                .opacity(state.undoStack.canRedo ? 1 : 0.35)

            barDivider

            ZoomControls()

            barDivider

            Button("Copy") { copyToClipboard() }
                .buttonStyle(GhostButtonStyle())
                .keyboardShortcut("c", modifiers: [.command])

            Button("Save") { save() }
                .buttonStyle(AccentButtonStyle())
                .keyboardShortcut("s", modifiers: [.command])
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [Theme.raisedTop, Theme.raisedBottom],
                        startPoint: .top, endPoint: .bottom
                    )
                )
        }
        .overlay(alignment: .top) {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Theme.topHighlight, lineWidth: 1)
                .mask(LinearGradient(colors: [.white, .clear], startPoint: .top, endPoint: .center))
        }
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.black.opacity(0.4), lineWidth: 1)
                .mask(LinearGradient(colors: [.clear, .black], startPoint: .center, endPoint: .bottom))
        }
        .shadow(color: .black.opacity(0.55), radius: 18, y: 9)
    }

    private var barDivider: some View {
        Rectangle().fill(Theme.hairline).frame(width: 1, height: 16)
    }

    private func copyToClipboard() {
        guard let pngData = renderPNG() else {
            NSSound.beep()
            return
        }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        if !pasteboard.setData(pngData, forType: .png) {
            NSSound.beep()
        }
    }

    private func save() {
        guard let pngData = renderPNG() else {
            NSSound.beep()
            return
        }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.png]
        panel.canCreateDirectories = true
        panel.nameFieldStringValue = defaultFilename()
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            do {
                try pngData.write(to: url, options: .atomic)
            } catch {
                NSSound.beep()
            }
        }
    }

    private func renderPNG() -> Data? {
        guard let cgImage = DocumentRenderer.render(state.document) else { return nil }
        return NSBitmapImageRep(cgImage: cgImage).representation(using: .png, properties: [:])
    }

    private func defaultFilename() -> String {
        let slug = state.document.pageTitle
            .lowercased()
            .replacingOccurrences(of: #"[^a-z0-9]+"#, with: "-", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        let base = slug.isEmpty ? "clipshot" : slug
        let stamp = ISO8601DateFormatter().string(from: Date())
            .replacingOccurrences(of: ":", with: "-")
        return "\(base)-\(stamp).png"
    }
}

private struct ZoomControls: View {
    // P0 placeholder: shows fixed "100%". Live zoom binding deferred to a follow-up —
    // wiring NSScrollView.magnification into SwiftUI adds risk to this PR.
    var body: some View {
        HStack(spacing: 2) {
            BarIconButton(systemName: "minus")
            Text("100%")
                .font(Theme.mono(11, .semibold))
                .foregroundStyle(Theme.textSecondary)
                .frame(minWidth: 42)
            BarIconButton(systemName: "plus")
        }
        .disabled(true)
        .help("Use trackpad pinch or ⌘+scroll to zoom (P0)")
    }
}
