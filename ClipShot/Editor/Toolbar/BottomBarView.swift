import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct BottomBarView: View {
    @ObservedObject var state: EditorState

    var body: some View {
        HStack(spacing: 8) {
            Group {
                Button(action: { state.performUndo() }) {
                    Image(systemName: "arrow.uturn.backward")
                }
                .disabled(!state.undoStack.canUndo)

                Button(action: { state.performRedo() }) {
                    Image(systemName: "arrow.uturn.forward")
                }
                .disabled(!state.undoStack.canRedo)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)

            Divider().frame(height: 14)

            ZoomControls()

            Divider().frame(height: 14)

            Button("Copy") { copyToClipboard() }
                .keyboardShortcut("c", modifiers: [.command])

            Button("Save") { save() }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut("s", modifiers: [.command])
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.5), radius: 12, y: 6)
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
        HStack(spacing: 4) {
            Button(action: {}) { Image(systemName: "minus") }
            Text("100%").font(.system(size: 11, weight: .medium).monospacedDigit())
                .frame(minWidth: 42)
            Button(action: {}) { Image(systemName: "plus") }
        }
        .buttonStyle(.plain)
        .foregroundStyle(.secondary)
        .disabled(true)
        .help("Use trackpad pinch or ⌘+scroll to zoom (P0)")
    }
}
