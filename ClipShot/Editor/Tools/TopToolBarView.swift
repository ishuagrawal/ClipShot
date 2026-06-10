import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// Floating top bar: brand mark, the capture's editable title, then history and
/// the two ways out. Document identity and document-level commands live up here;
/// the dock below the stage keeps only the in-canvas hands (tools, zoom).
struct TopBarView: View {
    @ObservedObject var state: EditorState
    @FocusState private var titleFocused: Bool

    var body: some View {
        HStack(spacing: 10) {
            HStack(spacing: 7) {
                BrandTickGlyph()
                    .frame(width: 12, height: 12)
                Text("ClipShot")
                    .font(Theme.title(12.5))
                    .foregroundStyle(Theme.textPrimary)
            }
            .accessibilityHidden(true)

            Rectangle()
                .fill(Theme.hairlineStrong)
                .frame(width: 1, height: 14)

            titleField

            Spacer(minLength: 12)

            IconButton(systemName: "arrow.uturn.backward") { state.performUndo() }
                .accessibilityLabel("Undo")
                .disabled(!state.undoStack.canUndo)
                .opacity(state.undoStack.canUndo ? 1 : 0.35)
                .help("Undo")

            IconButton(systemName: "arrow.uturn.forward") { state.performRedo() }
                .accessibilityLabel("Redo")
                .disabled(!state.undoStack.canRedo)
                .opacity(state.undoStack.canRedo ? 1 : 0.35)
                .help("Redo")

            Rectangle()
                .fill(Theme.hairlineStrong)
                .frame(width: 1, height: 14)

            exportButtons
        }
        .padding(.leading, 14)
        .padding(.trailing, 8)
        .frame(height: 44)
        .glassPanel(cornerRadius: 22)
    }

    /// The capture's name, editable in place. Doubles as the export filename.
    private var titleField: some View {
        TextField(
            "Untitled capture",
            text: Binding(
                get: { state.document.pageTitle },
                set: { state.document.pageTitle = $0 }
            )
        )
        .textFieldStyle(.plain)
        .font(Theme.label(12))
        .foregroundStyle(titleFocused ? Theme.textPrimary : Theme.textSecondary)
        .focused($titleFocused)
        .onSubmit { titleFocused = false }
        .frame(maxWidth: 260)
        .accessibilityLabel("Capture title")
    }

    /// Liquid Glass action buttons on macOS 26; flat capsules otherwise.
    @ViewBuilder
    private var exportButtons: some View {
        if #available(macOS 26.0, *) {
            Button("Copy") { copyToClipboard() }
                .buttonStyle(.glass)
                .help("Copy PNG to clipboard")
            Button("Save…") { save() }
                .buttonStyle(.glassProminent)
                .tint(Theme.accent)
                .help("Export PNG")
        } else {
            Button("Copy") { copyToClipboard() }
                .buttonStyle(GhostButtonStyle())
                .help("Copy PNG to clipboard")
            Button("Save…") { save() }
                .buttonStyle(AccentButtonStyle())
                .help("Export PNG")
        }
    }

    // MARK: - Export

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
