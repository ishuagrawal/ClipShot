import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// Floating controls just below the titlebar strip: the brand tick and the
/// capture's editable title ride a glass plate on the left; the two ways out
/// (Copy / Save) float chromeless on the right. The title doubles as the export
/// filename; the app name itself lives in the titlebar strip with the stoplights.
struct TitleBarView: View {
    @ObservedObject var state: EditorState
    /// Returns to the home page, keeping the capture in recents.
    var onGoHome: () -> Void = {}
    @FocusState private var titleFocused: Bool
    @State private var brandHovered = false

    var body: some View {
        // Top-aligned so a wrapped (two-line) title grows downward while the
        // export buttons hold the bar line.
        HStack(alignment: .top) {
            // The title rides on a dissolving plate: grounded at the brand
            // tick, fading to nothing toward the right, so the long field
            // never reads as a box.
            HStack(spacing: 9) {
                Button(action: onGoHome) {
                    BrandMarkGlyph()
                        .frame(width: 34, height: 34)
                        .overlay(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .strokeBorder(Theme.accent, lineWidth: 1.5)
                                .padding(3)
                                .opacity(brandHovered ? 1 : 0)
                        )
                        .scaleEffect(brandHovered ? 1.12 : 1)
                        .animation(.spring(response: 0.32, dampingFraction: 0.55), value: brandHovered)
                }
                .buttonStyle(.plain)
                .onHover { hovering in
                    brandHovered = hovering
                    if hovering { NSCursor.pointingHand.push() } else { NSCursor.pop() }
                }
                .help("Back to home")
                .accessibilityLabel("Back to home")
                titleField
            }
            // The icon sets the plate's visual register: equal 8pt breathing
            // room on its top, left, and bottom; the trailing side stays wider
            // for the dissolving field.
            .padding(.leading, 8)
            .padding(.trailing, Theme.panelInset)
            .padding(.vertical, 8)
            .frame(minHeight: Theme.topBarHeight)
            .floatingGlassPanel(glow: titleFocused)
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Capture title")

            Spacer(minLength: 16)

            // The ways out float bare on the stage: the accent Save capsule is
            // the only solid object up here, Copy reveals itself on hover.
            HStack(spacing: 10) {
                Button {
                    copyToClipboard()
                } label: {
                    Label("Copy", systemImage: "square.on.square")
                        .labelStyle(.titleAndIcon)
                }
                .buttonStyle(BareButtonStyle())
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
            .frame(height: Theme.topBarHeight)
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Export")
        }
        .frame(maxWidth: .infinity)
    }

    private var titleField: some View {
        // Vertical axis lets a long title wrap to a second line instead of
        // running under the export buttons; the flexible width (instead of a
        // fixed 380) lets the plate shrink when the buttons' image-aligned
        // position squeezes the bar.
        TextField(
            "Untitled capture",
            text: Binding(
                get: { state.document.sourceTitle },
                set: { state.document.sourceTitle = $0 }
            ),
            axis: .vertical
        )
        .lineLimit(2)
        .textFieldStyle(.plain)
        .font(Theme.title(13.5))
        .foregroundStyle(titleFocused ? Theme.textPrimary : Theme.textSecondary)
        .focused($titleFocused)
        .onSubmit { titleFocused = false }
        .frame(minWidth: 120, maxWidth: 380, alignment: .leading)
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
        // Exactly the titlebar text; only the path separator is illegal in a name.
        let title = state.document.sourceTitle
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "/", with: "-")
        let base = title.isEmpty ? "Untitled capture" : title
        return "\(base).png"
    }
}
