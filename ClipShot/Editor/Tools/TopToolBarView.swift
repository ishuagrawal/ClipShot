import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// Floating controls just below the titlebar strip: two separate glass pods —
/// brand tick and the capture's editable title on the left, the two ways out
/// (Copy / Save) on the right. The title doubles as the export filename; the
/// app name itself lives in the titlebar strip with the stoplights.
struct TitleBarView: View {
    @ObservedObject var state: EditorState
    @FocusState private var titleFocused: Bool

    var body: some View {
        HStack(alignment: .center) {
            // The title is a heading, not another control pod: bare type over
            // the stage, marked by the brand tick, with a hairline that ignites
            // to the accent while editing.
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 9) {
                    BrandTickGlyph()
                        .frame(width: 11, height: 11)
                    titleField
                }
                Rectangle()
                    .fill(titleFocused ? Theme.accent : Theme.hairlineStrong)
                    .frame(width: titleFocused ? 230 : 28, height: 1)
                    .padding(.leading, 20)
                    .animation(.easeOut(duration: 0.18), value: titleFocused)
            }
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Capture title")

            Spacer(minLength: 16)

            HStack(spacing: 8) {
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
            .padding(.horizontal, 12)
            .frame(height: Theme.topBarHeight)
            .glassPanel()
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Export")
        }
        .frame(maxWidth: .infinity)
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
        .font(Theme.title(13.5))
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
