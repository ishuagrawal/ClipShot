import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct EditorView: View {
    @ObservedObject var store: DOMCaptureSessionStore

    var body: some View {
        Group {
            if let session = store.session {
                EditorShell(session: session)
            } else {
                EmptyEditorView()
            }
        }
        .preferredColorScheme(.dark)
    }
}

private struct EditorShell: View {
    let session: DOMCaptureSession

    var body: some View {
        VStack(spacing: 0) {
            EditorTopBar(session: session)

            Rectangle()
                .fill(Color.white.opacity(0.08))
                .frame(height: 1)

            HStack(spacing: 0) {
                EditorToolSidebar()

                Rectangle()
                    .fill(Color.white.opacity(0.07))
                    .frame(width: 1)

                EditorCanvasView(session: session)

                Rectangle()
                    .fill(Color.white.opacity(0.08))
                    .frame(width: 1)

                EditorInspectorView(session: session)
            }
        }
        .background(Color(red: 0.055, green: 0.057, blue: 0.06))
    }
}

private struct EditorTopBar: View {
    let session: DOMCaptureSession

    var body: some View {
        ZStack {
            HStack {
                Spacer()

                Label("ClipShot", systemImage: "crop")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.secondary)

                Spacer()
            }

            HStack(spacing: 10) {
                Spacer()

                Button {
                    copySelectedCrop()
                } label: {
                    Label("Copy", systemImage: "doc.on.doc")
                }

                Button {
                    exportSelectedCrop()
                } label: {
                    Label("Export", systemImage: "square.and.arrow.down")
                }
                .buttonStyle(.borderedProminent)
            }
            .padding(.trailing, 16)
        }
        .frame(height: 52)
        .background(.thinMaterial)
    }

    private func copySelectedCrop() {
        guard let data = session.selectedCropPNGData() else {
            NSSound.beep()
            return
        }

        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setData(data, forType: .png)
    }

    private func exportSelectedCrop() {
        guard let data = session.selectedCropPNGData() else {
            NSSound.beep()
            return
        }

        let panel = NSSavePanel()
        panel.allowedContentTypes = [.png]
        panel.canCreateDirectories = true
        panel.nameFieldStringValue = defaultExportFilename

        panel.begin { response in
            guard response == .OK, let url = panel.url else {
                return
            }

            do {
                try data.write(to: url, options: .atomic)
            } catch {
                NSSound.beep()
            }
        }
    }

    private var defaultExportFilename: String {
        let sanitizedTitle = session.pageTitle
            .lowercased()
            .replacingOccurrences(of: #"[^a-z0-9]+"#, with: "-", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: "-"))

        return "\(sanitizedTitle.nilIfEmpty ?? "clipshot")-selection.png"
    }
}

private struct EditorToolSidebar: View {
    private let tools: [ToolItem] = [
        ToolItem(symbol: "pointer", label: "Cursor", isActive: false),
        ToolItem(symbol: "sparkle", label: "DOM", isActive: true),
        ToolItem(symbol: "crop", label: "Crop", isActive: false),
        ToolItem(symbol: "photo", label: "Image", isActive: false),
        ToolItem(symbol: "textformat", label: "Text", isActive: false),
        ToolItem(symbol: "slider.horizontal.3", label: "Tune", isActive: false)
    ]

    var body: some View {
        VStack(spacing: 20) {
            ForEach(tools) { tool in
                Image(systemName: tool.symbol)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(tool.isActive ? Color.white : Color.white.opacity(0.56))
                    .frame(width: 38, height: 38)
                    .background {
                        if tool.isActive {
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(Color.blue)
                                .shadow(color: .blue.opacity(0.35), radius: 14, x: 0, y: 4)
                        }
                    }
                    .help(tool.label)
            }

            Spacer()
        }
        .padding(.top, 72)
        .frame(width: 64)
        .background(Color.black.opacity(0.25))
    }
}

private struct ToolItem: Identifiable {
    let symbol: String
    let label: String
    let isActive: Bool

    var id: String {
        label
    }
}

private struct EditorCanvasView: View {
    let session: DOMCaptureSession

    var body: some View {
        GeometryReader { proxy in
            let imageFrame = fittedImageFrame(imageSize: session.imagePixelSize, containerSize: proxy.size)
            let selectionFrame = displayRect(for: session.selectedRect, in: imageFrame)

            ZStack {
                GridBackground()

                Image(nsImage: session.screenshotImage)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fit)
                    .frame(width: imageFrame.width, height: imageFrame.height)
                    .position(x: imageFrame.midX, y: imageFrame.midY)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .shadow(color: .black.opacity(0.45), radius: 24, x: 0, y: 18)

                SelectionOverlay(frame: selectionFrame)
            }
        }
        .background(Color(red: 0.035, green: 0.038, blue: 0.043))
    }

    private func fittedImageFrame(imageSize: CGSize, containerSize: CGSize) -> CGRect {
        let padding: CGFloat = 48
        let availableWidth = max(1, containerSize.width - padding * 2)
        let availableHeight = max(1, containerSize.height - padding * 2)
        let scale = min(availableWidth / max(1, imageSize.width), availableHeight / max(1, imageSize.height))
        let width = imageSize.width * scale
        let height = imageSize.height * scale

        return CGRect(
            x: (containerSize.width - width) / 2,
            y: (containerSize.height - height) / 2,
            width: width,
            height: height
        )
    }

    private func displayRect(for rect: DOMCaptureRect, in imageFrame: CGRect) -> CGRect {
        let scaleX = imageFrame.width / max(1, CGFloat(session.viewport.width))
        let scaleY = imageFrame.height / max(1, CGFloat(session.viewport.height))

        return CGRect(
            x: imageFrame.minX + CGFloat(rect.left) * scaleX,
            y: imageFrame.minY + CGFloat(rect.top) * scaleY,
            width: CGFloat(rect.width) * scaleX,
            height: CGFloat(rect.height) * scaleY
        )
    }
}

private struct SelectionOverlay: View {
    let frame: CGRect

    var body: some View {
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.blue.opacity(0.12))

            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Color(red: 0.1, green: 0.58, blue: 1.0), lineWidth: 3)

            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Color.white.opacity(0.62), lineWidth: 1)
                .padding(3)

            Text("Selected")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(
                    Capsule()
                        .fill(Color.blue)
                )
                .offset(x: 10, y: -26)
        }
        .frame(width: max(1, frame.width), height: max(1, frame.height))
        .position(x: frame.midX, y: frame.midY)
        .shadow(color: .blue.opacity(0.28), radius: 18, x: 0, y: 0)
    }
}

private struct GridBackground: View {
    var body: some View {
        Canvas { context, size in
            let spacing: CGFloat = 24
            let color = Color.white.opacity(0.08)

            var y: CGFloat = 12
            while y < size.height {
                var x: CGFloat = 12
                while x < size.width {
                    let dot = Path(ellipseIn: CGRect(x: x, y: y, width: 1.2, height: 1.2))
                    context.fill(dot, with: .color(color))
                    x += spacing
                }
                y += spacing
            }
        }
    }
}

private struct EditorInspectorView: View {
    let session: DOMCaptureSession

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Label("Inspector", systemImage: "slider.horizontal.3")
                .font(.system(size: 14, weight: .semibold))
                .padding(.horizontal, 18)
                .frame(height: 52)

            Rectangle()
                .fill(Color.white.opacity(0.08))
                .frame(height: 1)

            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("SMART DOM CROPPER")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(.secondary)
                            .tracking(1.2)

                        HStack(alignment: .top, spacing: 12) {
                            Image(systemName: "rectangle.3.group")
                                .font(.system(size: 22, weight: .medium))
                                .foregroundStyle(.blue)
                                .frame(width: 28)

                            Text("The extension sent the visible page screenshot and selected DOM bounds. ClipShot is rendering both here for tuning.")
                                .font(.system(size: 13))
                                .foregroundStyle(.primary.opacity(0.86))
                                .lineSpacing(4)
                        }
                        .padding(14)
                        .background {
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(Color.blue.opacity(0.16))
                                .overlay {
                                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                                        .stroke(Color.blue.opacity(0.55), lineWidth: 1)
                                }
                        }
                    }

                    InspectorSection(title: "Selection") {
                        InspectorRow(label: "CSS bounds", value: formattedCSSRect)
                        InspectorRow(label: "Pixel crop", value: formattedPixelRect)
                        InspectorRow(label: "DOM depth", value: selectedCandidate?.depth.description ?? "-")
                    }

                    InspectorSection(title: "Page") {
                        InspectorRow(label: "Title", value: session.pageTitle)
                        if !session.pageURL.isEmpty {
                            InspectorRow(label: "URL", value: session.pageURL)
                        }
                        InspectorRow(label: "Viewport", value: "\(Int(session.viewport.width)) x \(Int(session.viewport.height))")
                        InspectorRow(label: "Image", value: "\(Int(session.imagePixelSize.width)) x \(Int(session.imagePixelSize.height))")
                    }

                    InspectorSection(title: "Candidates") {
                        InspectorRow(label: "Detected", value: "\(session.candidates.count)")
                        InspectorRow(label: "Selected index", value: "\(session.selectedIndex + 1)")
                    }
                }
                .padding(18)
            }
        }
        .frame(width: 320)
        .background(Color.black.opacity(0.18))
    }

    private var selectedCandidate: DOMCandidateSnapshot? {
        session.candidates.first(where: { $0.selected }) ??
        session.candidates.first(where: { $0.id == session.selectedIndex })
    }

    private var formattedCSSRect: String {
        "\(Int(session.selectedRect.left)), \(Int(session.selectedRect.top))  \(Int(session.selectedRect.width)) x \(Int(session.selectedRect.height))"
    }

    private var formattedPixelRect: String {
        let rect = session.pixelRect(for: session.selectedRect)
        return "\(Int(rect.origin.x)), \(Int(rect.origin.y))  \(Int(rect.width)) x \(Int(rect.height))"
    }
}

private struct InspectorSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title.uppercased())
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(.secondary)
                .tracking(1.1)

            VStack(spacing: 10) {
                content
            }
        }
    }
}

private struct InspectorRow: View {
    let label: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)

            Text(value)
                .font(.system(size: 12))
                .foregroundStyle(.primary.opacity(0.86))
                .lineLimit(3)
                .textSelection(.enabled)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct EmptyEditorView: View {
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "crop")
                .font(.system(size: 34, weight: .medium))
                .foregroundStyle(.secondary)

            Text("No capture session")
                .font(.headline)
        }
        .frame(minWidth: 860, minHeight: 560)
        .background(Color(red: 0.055, green: 0.057, blue: 0.06))
        .foregroundStyle(.secondary)
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
