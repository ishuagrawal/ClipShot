import AppKit

/// Shared PNG export used by both the toolbar buttons and the keyboard shortcuts,
/// so the two paths stay identical.
@MainActor
enum ExportActions {
    static func copyToClipboard(_ document: EditorDocument) {
        guard let pngData = renderPNG(document) else { NSSound.beep(); return }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        if !pasteboard.setData(pngData, forType: .png) { NSSound.beep() }
    }

    static func save(_ document: EditorDocument) {
        guard let pngData = renderPNG(document) else { NSSound.beep(); return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.png]
        panel.canCreateDirectories = true
        panel.nameFieldStringValue = defaultFilename(document)
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            do { try pngData.write(to: url, options: .atomic) } catch { NSSound.beep() }
        }
    }

    private static func renderPNG(_ document: EditorDocument) -> Data? {
        guard let cgImage = DocumentRenderer.render(document) else { return nil }
        return NSBitmapImageRep(cgImage: cgImage).representation(using: .png, properties: [:])
    }

    private static func defaultFilename(_ document: EditorDocument) -> String {
        let title = document.sourceTitle
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "/", with: "-")
        return "\(title.isEmpty ? "Untitled capture" : title).png"
    }
}
