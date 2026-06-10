import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// Full-width glass bar across the top of the window, running under the traffic
/// lights: brand and the capture's editable title on the left, the two ways out
/// (Copy / Save) on the right. The title doubles as the export filename.
struct TitleBarView: View {
    @ObservedObject var state: EditorState
    @FocusState private var titleFocused: Bool

    var body: some View {
        HStack(spacing: 9) {
            BrandTickGlyph()
                .frame(width: 12, height: 12)
            Text("ClipShot")
                .font(Theme.title(12.5))
                .foregroundStyle(Theme.textPrimary)
            Rectangle()
                .fill(Theme.hairlineStrong)
                .frame(width: 1, height: 13)
            titleField
            Spacer(minLength: 16)
            Button {
                copyToClipboard()
            } label: {
                Label("Copy", systemImage: "square.on.square")
                    .labelStyle(.titleAndIcon)
            }
            .buttonStyle(GhostButtonStyle())
            .help("Copy PNG to clipboard")
            Button {
                save()
            } label: {
                Label("Save", systemImage: "square.and.arrow.down")
                    .labelStyle(.titleAndIcon)
            }
            .buttonStyle(AccentButtonStyle())
            .help("Export PNG")
        }
        // Clear of the traffic lights on the left; symmetric breathing room right.
        .padding(.leading, 86)
        .padding(.trailing, Theme.chromeMargin)
        .frame(height: Theme.topBarHeight)
        .frame(maxWidth: .infinity)
        .glassPanel(cornerRadius: 0)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Theme.hairline)
                .frame(height: 1)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Title bar")
    }

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
        .frame(width: 230)
        .help("Capture title — used as the export filename")
        .accessibilityLabel("Capture title")
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
