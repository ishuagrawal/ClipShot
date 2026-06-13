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
            DriftField()
            VStack(spacing: 36) {
                VStack(spacing: 22) {
                    HomeBrandLockup()
                    HomeHeroCard(onOpenFile: openFilePanel, isDropTargeted: isDropTargeted)
                }
                .opacity(appeared ? 1 : 0)
                .scaleEffect(appeared ? 1 : 0.985)
                if !recents.entries.isEmpty {
                    recentsStrip
                        .opacity(appeared ? 1 : 0)
                        .transition(.opacity.combined(with: .scale(scale: 0.97)))
                }
            }
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
                .padding(.leading, 6)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 14) {
                    ForEach(recents.entries) { entry in
                        RecentThumbnailCell(
                            entry: entry,
                            imageURL: recents.imageURL(for: entry),
                            onOpen: { onReopenRecent(entry) },
                            onRemove: { recents.remove(entry.id) }
                        )
                        .scrollTransition(.interactive, axis: .horizontal) { content, phase in
                            content
                                .blur(radius: abs(phase.value) * abs(phase.value) * 10)
                                .opacity(1 - abs(phase.value) * abs(phase.value) * 0.92)
                        }
                    }
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 8)
            }
            .defaultScrollAnchor(.leading)
            .contentMargins(.horizontal, 44, for: .scrollContent)
            .mask {
                LinearGradient(
                    stops: [
                        .init(color: .clear, location: 0),
                        .init(color: .black, location: 0.05),
                        .init(color: .black, location: 0.95),
                        .init(color: .clear, location: 1)
                    ],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            }
        }
        .frame(maxWidth: 720)
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
            ImportIconButton(isDropTargeted: isDropTargeted, action: onOpenFile)
                .padding(.bottom, 16)
            Text("Capture a component")
                .font(Theme.title(15))
                .foregroundStyle(Theme.textPrimary)
                .padding(.bottom, 20)
            HStack(spacing: 8) {
                GlassGroup(spacing: 5) {
                    HStack(spacing: 5) {
                        Keycap(text: "⌃", glass: true)
                        Keycap(text: "⇧", glass: true)
                        Keycap(text: "5", glass: true)
                    }
                }
                Text("anywhere on screen")
                    .font(Theme.label(12))
                    .foregroundStyle(Theme.textSecondary)
                    .padding(.leading, 4)
            }
            .padding(.bottom, 18)
            Text("or drop an image here")
                .font(Theme.label(12))
                .foregroundStyle(Theme.textTertiary)
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

/// Brand lockup above the hero: logo with a warm halo, tracked wordmark, and a
/// registration-framed tagline — drafting-room styling, not a generic title stack.
private struct HomeBrandLockup: View {
    var body: some View {
        VStack(spacing: 16) {
            BrandMarkGlyph()
                .frame(width: 66, height: 66)
                .shadow(color: Theme.floatShadow, radius: 10, y: 4)
            Text("ClipShot")
                .font(Theme.title(30, .semibold))
                .tracking(1.5)
                .foregroundStyle(Theme.textPrimary)
            HStack(spacing: 12) {
                rule
                Text("Beautiful screenshots, instantly".uppercased())
                    .font(Theme.section(10.5, .semibold))
                    .tracking(2.4)
                    .foregroundStyle(Theme.accentText)
                rule
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("ClipShot — beautiful screenshots, instantly")
    }

    private var rule: some View {
        Rectangle()
            .fill(Theme.hairlineStrong)
            .frame(width: 26, height: 1)
    }
}

/// The import glyph doubles as the open-file button; brightens with a soft accent
/// halo on hover so it reads as clickable.
private struct ImportIconButton: View {
    var isDropTargeted: Bool
    var action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: "square.and.arrow.down")
                .font(.system(size: 26, weight: .regular))
                .foregroundStyle(isDropTargeted || hovering ? Theme.accentText : Theme.textTertiary)
                .frame(width: 56, height: 56)
                .background(Circle().fill(Theme.accentDim).opacity(hovering ? 1 : 0))
                .scaleEffect(hovering ? 1.06 : 1)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.14), value: hovering)
        .help("Open an image…")
        .accessibilityLabel("Open an image")
    }
}

/// `GlassEffectContainer` on macOS 26 so adjacent glass merges cleanly; passthrough below.
private struct GlassGroup<Content: View>: View {
    var spacing: CGFloat = 6
    @ViewBuilder var content: () -> Content

    var body: some View {
        if #available(macOS 26.0, *) {
            GlassEffectContainer(spacing: spacing) { content() }
        } else {
            content()
        }
    }
}

/// Real `glassEffect` behind an arbitrary shape on macOS 26; solid inset fallback below.
private struct GlassBackground<S: Shape>: ViewModifier {
    var shape: S
    var interactive: Bool = false

    func body(content: Content) -> some View {
        if #available(macOS 26.0, *) {
            content.glassEffect(interactive ? .regular.interactive() : .regular, in: shape)
        } else {
            content
                .background(shape.fill(Theme.inputFill))
                .overlay(shape.stroke(Theme.hairlineStrong, lineWidth: 1))
        }
    }
}

private extension View {
    func glassBackground<S: Shape>(_ shape: S, interactive: Bool = false) -> some View {
        modifier(GlassBackground(shape: shape, interactive: interactive))
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

    private static let height: CGFloat = 120
    private static let tileRadius: CGFloat = Theme.radiusPanel
    private static let imageRadius: CGFloat = Theme.radiusControl + 3

    private static let width: CGFloat = 184

    var body: some View {
        Button(action: onOpen) {
            imageCell
                .padding(7)
                .background { tile }
                .brightness(hovering ? 0.05 : 0)
                .shadow(color: Theme.floatShadow.opacity(hovering ? 0.9 : 0), radius: 12, y: 6)
                .offset(y: hovering ? -3 : 0)
                .contentShape(RoundedRectangle(cornerRadius: Self.tileRadius, style: .continuous))
        }
        .buttonStyle(.plain)
        .overlay(alignment: .topTrailing) { removeButton }
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.16), value: hovering)
        .task {
            guard thumbnail == nil else { return }
            let maxPixel = max(Self.width, Self.height) * 2
            thumbnail = await Self.decodeThumbnail(url: imageURL, maxPixel: maxPixel)
        }
        .help(title)
        .accessibilityLabel("\(title), \(relativeDate)")
        .accessibilityAction(named: "Remove from recents", onRemove)
    }

    private var imageCell: some View {
        ZStack {
            Theme.inputFill
            if let thumbnail {
                Image(decorative: thumbnail, scale: 1)
                    .resizable()
                    .scaledToFill()
            }
        }
        .frame(width: Self.width, height: Self.height)
        .overlay(alignment: .bottom) { caption }
        .clipShape(RoundedRectangle(cornerRadius: Self.imageRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Self.imageRadius, style: .continuous)
                .strokeBorder(hovering ? Theme.hairlineStrong : Theme.hairline, lineWidth: 1)
        )
    }

    // Barely-visible glass frame around the preview — depth only.
    private var tile: some View {
        RoundedRectangle(cornerRadius: Self.tileRadius, style: .continuous)
            .fill(.clear)
            .glassBackground(RoundedRectangle(cornerRadius: Self.tileRadius, style: .continuous))
            .opacity(hovering ? 0.5 : 0.3)
    }

    private var title: String { entry.sourceTitle ?? "Untitled" }

    private var relativeDate: String {
        Self.dateFormatter.localizedString(for: entry.capturedAt, relativeTo: Date())
    }

    private var caption: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(Theme.label(11, .semibold))
                .foregroundStyle(Theme.textPrimary)
                .lineLimit(1)
            Text(relativeDate)
                .font(Theme.mono(9))
                .foregroundStyle(Theme.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 9)
        .padding(.top, 18)
        .padding(.bottom, 7)
        .background(
            LinearGradient(colors: [.clear, .black.opacity(0.72)],
                           startPoint: .top, endPoint: .bottom)
        )
        .opacity(hovering ? 1 : 0)
    }

    private var removeButton: some View {
        Button(action: onRemove) {
            Image(systemName: "xmark")
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(Theme.textPrimary)
                .frame(width: 22, height: 22)
                .glassBackground(Circle(), interactive: true)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .padding(7)
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
