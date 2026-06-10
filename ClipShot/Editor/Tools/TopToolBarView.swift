import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// Floating identity chip, sitting to the right of the traffic lights: the brand
/// tick, the wordmark, and the capture's page title in one quiet glass capsule.
struct TitleChipView: View {
    @ObservedObject var state: EditorState

    var body: some View {
        HStack(spacing: 9) {
            BrandTickGlyph()
                .frame(width: 12, height: 12)
            Text("ClipShot")
                .font(Theme.title(12.5))
                .foregroundStyle(Theme.textPrimary)
            if !state.document.pageTitle.isEmpty {
                Rectangle()
                    .fill(Theme.hairlineStrong)
                    .frame(width: 1, height: 12)
                Text(state.document.pageTitle)
                    .font(Theme.label(11.5))
                    .foregroundStyle(Theme.textTertiary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .frame(maxWidth: 260)
                    .fixedSize(horizontal: true, vertical: false)
            }
        }
        .padding(.horizontal, 14)
        .frame(height: 36)
        .glassPanel(cornerRadius: 18)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("ClipShot — \(state.document.pageTitle)")
    }
}

/// Export panel: pinned at the foot of the inspector column — the live output
/// size and the two ways out. The only solid vermilion button in the chrome.
struct ExportPanelView: View {
    @ObservedObject var state: EditorState

    var body: some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 1) {
                Text("PNG")
                    .font(Theme.section(9.5))
                    .foregroundStyle(Theme.textTertiary)
                Text(exportSizeText)
                    .font(Theme.mono(11, .semibold))
                    .foregroundStyle(Theme.textSecondary)
                    .lineLimit(1)
                    .fixedSize()
            }
            .accessibilityElement(children: .combine)
            Spacer(minLength: 8)
            Button("Copy") { copyToClipboard() }
                .buttonStyle(GhostButtonStyle())
                .help("Copy PNG to clipboard")
            Button("Save…") { save() }
                .buttonStyle(AccentButtonStyle())
                .help("Export PNG")
        }
        .padding(.horizontal, 14)
        .frame(width: Theme.inspectorWidth, height: 52)
        .glassPanel(cornerRadius: 26)
    }

    private var exportSizeText: String {
        let size = state.document.paddedDocumentSize
        return "\(Int(size.width.rounded())) × \(Int(size.height.rounded()))"
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
