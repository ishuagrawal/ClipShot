import AppKit
import ImageIO
import SwiftUI
import UniformTypeIdentifiers

/// Home page shown when no session is open: hero card plus a recents strip.
struct HomeView: View {
    @EnvironmentObject private var recents: RecentsStore
    var onReopenRecent: (RecentEntry) -> Void = { _ in }
    /// Import an opened/dropped image; false means it couldn't be read.
    var onImportFile: (URL) async -> Bool = { _ in false }
    var onImportData: (Data, String) async -> Bool = { _, _ in false }

    @State private var appeared = false
    @State private var isDropTargeted = false
    @State private var importErrorVisible = false
    @State private var errorDismissTask: Task<Void, Never>?
    @State private var filePanelOpen = false

    var body: some View {
        ZStack {
            StageBackdrop()
            StageCornerTicks()
            VStack(spacing: 40) {
                HomeHeroCard(onOpenFile: openFilePanel, isDropTargeted: isDropTargeted)
                if !recents.entries.isEmpty {
                    recentsStrip
                        .transition(.opacity.combined(with: .scale(scale: 0.97)))
                }
            }
            .opacity(appeared ? 1 : 0)
            .scaleEffect(appeared ? 1 : 0.985)
            .animation(Theme.panelSpring, value: recents.entries.map(\.id))
        }
        .overlay(alignment: .bottom) { importErrorNotice.padding(.bottom, 28) }
        .ignoresSafeArea()
        .frame(minWidth: 860, minHeight: 560)
        .onDrop(of: [.fileURL, .image], isTargeted: $isDropTargeted) { providers in
            handleDrop(providers)
        }
        .onAppear {
            recents.loadIfNeeded()
            withAnimation(.easeOut(duration: 0.35)) { appeared = true }
        }
    }

    // MARK: - Import

    private func openFilePanel() {
        guard !filePanelOpen else { return }
        filePanelOpen = true
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.begin { response in
            Task { @MainActor in
                filePanelOpen = false
                guard response == .OK, let url = panel.url else { return }
                await importFile(at: url)
            }
        }
    }

    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        guard let provider = providers.first else { return false }
        if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                Task { @MainActor in
                    if let url { await importFile(at: url) } else { showImportError() }
                }
            }
            return true
        }
        if provider.hasItemConformingToTypeIdentifier(UTType.image.identifier) {
            // Prefer the provider's concrete image type (public.png/jpeg) over the abstract one.
            let identifier = provider.registeredTypeIdentifiers
                .first { UTType($0)?.conforms(to: .image) == true } ?? UTType.image.identifier
            provider.loadDataRepresentation(forTypeIdentifier: identifier) { data, _ in
                Task { @MainActor in
                    guard let data, await onImportData(data, "Dropped Image") else {
                        showImportError()
                        return
                    }
                }
            }
            return true
        }
        return false
    }

    @MainActor
    private func importFile(at url: URL) async {
        if await !onImportFile(url) { showImportError() }
    }

    @MainActor
    private func showImportError() {
        errorDismissTask?.cancel()
        withAnimation(.easeOut(duration: 0.18)) { importErrorVisible = true }
        errorDismissTask = Task {
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: 0.3)) { importErrorVisible = false }
        }
    }

    /// Transient notice floating near the bottom edge, clear of the recents strip; auto-dismisses.
    private var importErrorNotice: some View {
        HStack(spacing: 6) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(Theme.danger)
            Text("Couldn't read that image")
                .font(Theme.label(11.5))
                .foregroundStyle(Theme.textPrimary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .glassPanel(cornerRadius: Theme.radiusPill)
        .opacity(importErrorVisible ? 1 : 0)
        .allowsHitTesting(false)
        .accessibilityHidden(!importErrorVisible)
    }

    private var recentsStrip: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionLabel(text: "Recent captures")
            HStack(spacing: 10) {
                ForEach(recents.entries.prefix(6)) { entry in
                    RecentThumbnailCell(
                        entry: entry,
                        imageURL: recents.imageURL(for: entry),
                        onOpen: { onReopenRecent(entry) },
                        onRemove: { recents.remove(entry.id) }
                    )
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Recent captures")
    }
}

// MARK: - Hero

private struct HomeHeroCard: View {
    var onOpenFile: () -> Void
    var isDropTargeted: Bool

    var body: some View {
        VStack(spacing: 0) {
            Image(systemName: "viewfinder")
                .font(.system(size: 30, weight: .regular))
                .foregroundStyle(isDropTargeted ? Theme.accentText : Theme.textTertiary)
                .padding(.bottom, 18)
            Text("Capture a component")
                .font(Theme.title(15))
                .foregroundStyle(Theme.textPrimary)
                .padding(.bottom, 20)
            HStack(spacing: 5) {
                Keycap(text: "⌃")
                Keycap(text: "⇧")
                Keycap(text: "5")
                Text("anywhere on screen")
                    .font(Theme.label(12))
                    .foregroundStyle(Theme.textSecondary)
                    .padding(.leading, 6)
            }
            .padding(.bottom, 18)
            HStack(spacing: 6) {
                Text("or drop an image here ·")
                    .font(Theme.label(12))
                    .foregroundStyle(Theme.textTertiary)
                OpenFileLink(action: onOpenFile)
            }
        }
        .padding(.horizontal, 44)
        .padding(.vertical, 40)
        .glassPanel(cornerRadius: 24)
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .strokeBorder(Theme.accent.opacity(0.75), lineWidth: 1.5)
                .shadow(color: Theme.accent.opacity(0.55), radius: 12)
                .opacity(isDropTargeted ? 1 : 0)
        )
        .animation(.easeOut(duration: 0.18), value: isDropTargeted)
    }
}

/// Vermilion text link for opening a file; brightens on hover.
private struct OpenFileLink: View {
    var action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Text("Open file…")
                .font(Theme.label(12, .medium))
                .foregroundStyle(hovering ? Theme.accent : Theme.accentText)
                .underline(hovering)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.12), value: hovering)
        .accessibilityLabel("Open file")
    }
}

// MARK: - Recents strip

private struct RecentThumbnailCell: View {
    let entry: RecentEntry
    let imageURL: URL
    var onOpen: () -> Void
    var onRemove: () -> Void

    @State private var thumbnail: CGImage?
    @State private var hovering = false

    private static let height: CGFloat = 80

    private var width: CGFloat {
        let aspect = entry.pixelHeight > 0
            ? CGFloat(entry.pixelWidth) / CGFloat(entry.pixelHeight) : 1
        return min(max(Self.height * aspect, 56), 120)
    }

    var body: some View {
        Button(action: onOpen) {
            ZStack {
                Theme.inputFill
                if let thumbnail {
                    Image(decorative: thumbnail, scale: 1)
                        .resizable()
                        .scaledToFill()
                }
            }
            .frame(width: width, height: Self.height)
            .overlay(alignment: .bottom) { caption }
            .clipShape(RoundedRectangle(cornerRadius: Theme.radiusControl + 2, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.radiusControl + 2, style: .continuous)
                    .strokeBorder(hovering ? Theme.hairlineStrong : Theme.hairline, lineWidth: 1)
            )
            .brightness(hovering ? 0.05 : 0)
            .shadow(color: Theme.floatShadow.opacity(hovering ? 1 : 0), radius: 10, y: 5)
            .offset(y: hovering ? -3 : 0)
            .contentShape(RoundedRectangle(cornerRadius: Theme.radiusControl + 2, style: .continuous))
        }
        .buttonStyle(.plain)
        .overlay(alignment: .topTrailing) { removeButton }
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.14), value: hovering)
        .task {
            guard thumbnail == nil else { return }
            let maxPixel = max(width, Self.height) * 2
            thumbnail = await Self.decodeThumbnail(url: imageURL, maxPixel: maxPixel)
        }
        .help(title)
        .accessibilityLabel("\(title), \(relativeDate)")
        .accessibilityAction(named: "Remove from recents", onRemove)
    }

    private var title: String { entry.sourceTitle ?? "Untitled" }

    private var relativeDate: String {
        Self.dateFormatter.localizedString(for: entry.capturedAt, relativeTo: Date())
    }

    private var caption: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(title)
                .font(Theme.label(10, .semibold))
                .foregroundStyle(Theme.textPrimary)
                .lineLimit(1)
            Text(relativeDate)
                .font(Theme.mono(8.5))
                .foregroundStyle(Theme.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 7)
        .padding(.top, 14)
        .padding(.bottom, 5)
        .background(
            LinearGradient(colors: [.clear, .black.opacity(0.72)],
                           startPoint: .top, endPoint: .bottom)
        )
        .opacity(hovering ? 1 : 0)
    }

    private var removeButton: some View {
        Button(action: onRemove) {
            Image(systemName: "xmark")
                .font(.system(size: 7.5, weight: .bold))
                .foregroundStyle(Theme.textPrimary)
                .frame(width: 16, height: 16)
                .background(Circle().fill(.black.opacity(0.6)))
                .overlay(Circle().stroke(Theme.hairlineStrong, lineWidth: 1))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .padding(4)
        .opacity(hovering ? 1 : 0)
        .offset(y: hovering ? -3 : 0)
        .help("Remove from recents")
        .accessibilityLabel("Remove \(title) from recents")
    }

    /// Decodes a downscaled thumbnail off the main thread; never the full PNG.
    private nonisolated static func decodeThumbnail(url: URL, maxPixel: CGFloat) async -> CGImage? {
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixel
        ]
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }

    private static let dateFormatter: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter
    }()
}
