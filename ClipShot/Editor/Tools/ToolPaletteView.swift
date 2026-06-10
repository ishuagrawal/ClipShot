import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// The dock: one floating glass bar under the stage — history, cursor tools,
/// zoom, and the two ways out, in working order left to right. Picking a draw
/// tool sets the canvas cursor mode; finishing a draw auto-returns to Select
/// (see `EditorState.commitDraw`).
struct DockView: View {
    @ObservedObject var state: EditorState
    @ObservedObject var zoom: CanvasZoomController

    private let tools: [(EditorTool, String?)] = [
        (.select, "V"),
        (.arrow, "A"),
        (.rectangle, "R"),
        (.text, "T")
    ]

    var body: some View {
        HStack(spacing: 4) {
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

            divider

            ForEach(tools, id: \.0) { tool, shortcut in
                ToolRailButton(
                    systemName: tool.symbolName,
                    label: tool.displayName,
                    shortcut: shortcut,
                    isActive: state.activeTool == tool
                ) {
                    state.selectCursorTool(tool)
                }
            }

            divider

            ZoomControlsView(zoom: zoom)

            divider

            exportButtons
        }
        .padding(.horizontal, 10)
        .frame(height: 52)
        .glassPanel(cornerRadius: 26)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Dock")
    }

    private var divider: some View {
        Rectangle()
            .fill(Theme.hairlineStrong)
            .frame(width: 1, height: 18)
            .padding(.horizontal, 7)
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
