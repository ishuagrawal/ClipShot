import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// Single command bar across the top. Left: wordmark. Center: capture title.
/// Right: history + export actions. Tools live in the left `ToolRailView`,
/// properties in the right `InspectorView`.
struct TopToolBarView: View {
    @ObservedObject var state: EditorState

    /// Clearance for the traffic lights (window uses `.fullSizeContentView`).
    private let trafficLightInset: CGFloat = 76

    var body: some View {
        HStack(spacing: 4) {
            wordmark
                .padding(.leading, trafficLightInset)

            Spacer(minLength: 12)

            Text(state.document.pageTitle)
                .font(Theme.label(12))
                .foregroundStyle(Theme.textTertiary)
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(maxWidth: 320)

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
                .fill(Theme.hairline)
                .frame(width: 1, height: 18)
                .padding(.horizontal, 8)

            Button("Copy") { copyToClipboard() }
                .buttonStyle(GhostButtonStyle())
                .help("Copy PNG to clipboard")

            Button("Save…") { save() }
                .buttonStyle(AccentButtonStyle())
                .help("Export PNG")
        }
        .padding(.trailing, 14)
        .frame(height: Theme.topBarHeight)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.surface)
    }

    /// Identity mark: a vermilion registration tick next to the name. Quiet on purpose.
    private var wordmark: some View {
        HStack(spacing: 7) {
            BrandTickGlyph()
                .frame(width: 13, height: 13)
            Text("ClipShot")
                .font(Theme.title(13))
                .foregroundStyle(Theme.textPrimary)
        }
        .accessibilityHidden(true)
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
