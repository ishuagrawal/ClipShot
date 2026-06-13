import AppKit
import ImageIO
import SwiftUI

/// Home page shown when no session is open: hero card plus a recents strip.
struct HomeView: View {
    @EnvironmentObject private var recents: RecentsStore
    var onReopenRecent: (RecentEntry) -> Void = { _ in }
    /// Open-file action and drop highlight are driven externally (Task 4).
    var onOpenFile: () -> Void = {}
    var isDropTargeted: Bool = false

    @State private var appeared = false

    var body: some View {
        ZStack {
            StageBackdrop()
            StageCornerTicks()
            VStack(spacing: 40) {
                HomeHeroCard(onOpenFile: onOpenFile, isDropTargeted: isDropTargeted)
                if !recents.entries.isEmpty {
                    recentsStrip
                        .transition(.opacity.combined(with: .scale(scale: 0.97)))
                }
            }
            .opacity(appeared ? 1 : 0)
            .scaleEffect(appeared ? 1 : 0.985)
            .animation(Theme.panelSpring, value: recents.entries.map(\.id))
        }
        .ignoresSafeArea()
        .frame(minWidth: 860, minHeight: 560)
        .onAppear {
            recents.loadIfNeeded()
            withAnimation(.easeOut(duration: 0.35)) { appeared = true }
        }
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
