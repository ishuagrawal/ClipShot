import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// Background detail panel: a Color / Gradient / Wallpaper section picker with
/// per-section controls, plus stackable blur + grain effects.
struct BackgroundToolView: View {
    @ObservedObject var state: EditorState

    private enum Section: String, CaseIterable, Identifiable {
        case color = "Color"
        case gradient = "Gradient"
        case wallpaper = "Wallpaper"
        var id: String { rawValue }

        var icon: String {
            switch self {
            case .color: return "paintpalette"
            case .gradient: return "circle.righthalf.filled"
            case .wallpaper: return "photo"
            }
        }

        init(_ kind: BackgroundStyle.Kind) {
            switch kind {
            case .none, .solid: self = .color
            case .gradient, .dynamic: self = .gradient
            case .wallpaper: self = .wallpaper
            }
        }
    }

    @State private var section: Section = .color
    @State private var solid = Color.white
    @State private var gradientStart = Color(cgColor: BackgroundStyle.defaultGradientStart)
    @State private var gradientEnd = Color(cgColor: BackgroundStyle.defaultGradientEnd)
    @State private var gradientAngle = Double(BackgroundStyle.defaultGradientAngle)
    @State private var blur = 0.0
    @State private var noise = 0.0
    @State private var uploads: [Wallpaper] = []
    @State private var isSyncingControls = false
    @State private var isSyncingEffects = false
    @State private var sectionOpacity: Double = 1
    @State private var sectionHeight: CGFloat = 0
    // Effects slot springs between zero and its measured height when the
    // background toggles to/from None — same mechanism as the inspector's
    // contextual card (explicit withAnimation on a measured height so the
    // glass surface interpolates, not the declarative `.animation(value:)`
    // that only the inner content frame would follow).
    @State private var effectsNaturalHeight: CGFloat = 0
    @State private var effectsHeight: CGFloat = 0
    @State private var effectsOpacity: Double = 1
    // The section actually rendered below the tabs. Decoupled from `section`
    // (the picker) so the page only ever swaps while invisible — no flash of
    // the outgoing page.
    @State private var visibleSection: Section = .color
    private static let sectionClipInset: CGFloat = 6

    private var style: BackgroundStyle { state.document.background }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
          VStack(alignment: .leading, spacing: Theme.panelSectionSpacing) {
            sectionTabs

            ZStack(alignment: .top) {
                VStack(alignment: .leading, spacing: Theme.panelRowSpacing) {
                    switch visibleSection {
                    case .color: colorSection
                    case .gradient: gradientSection
                    case .wallpaper: wallpaperSection
                    }
                }
                // Headroom on all edges so the clip doesn't shave the bead
                // ring/lift/shadow (vertical) or the edge swatches (horizontal).
                .padding(Self.sectionClipInset)
                .opacity(sectionOpacity)
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { height in
                    if sectionHeight != height {
                        withAnimation(Theme.panelSpring) { sectionHeight = height }
                    }
                }
            }
            // Clip to an animated height so the rows are revealed as the panel
            // grows instead of fading in over empty space.
            .frame(height: sectionHeight, alignment: .top)
            .clipped()
            // Cancel the clip headroom so layout/alignment is unchanged.
            .padding(-Self.sectionClipInset)
          }
          // No background = no effects. The slot's height springs to zero and
          // the glass sliders fade, so the whole Background card shortens on
          // the panel spring — same as the inspector's contextual card. The
          // section's inter-row gap is folded into the measured content so it
          // collapses with the slot.
          effects
            .padding(.top, Theme.panelSectionSpacing)
            .opacity(effectsOpacity)
            .allowsHitTesting(style.kind != .none)
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { natural in
                effectsNaturalHeight = natural
                if style.kind != .none, effectsHeight != natural {
                    effectsHeight = natural
                }
            }
            .frame(height: effectsHeight, alignment: .top)
            .clipped()
        }
        .onChange(of: style.kind == .none) { _, isNone in
            withAnimation(Theme.panelSpring) {
                effectsHeight = isNone ? 0 : effectsNaturalHeight
                effectsOpacity = isNone ? 0 : 1
            }
        }
        // Instant-cut + single fade-up, matching the annotation tools' speed.
        .onChange(of: section) { _, newSection in
            guard newSection != visibleSection else { return }
            var snap = Transaction()
            snap.disablesAnimations = true
            withTransaction(snap) {
                sectionOpacity = 0
                visibleSection = newSection
            }
            withAnimation(.easeOut(duration: 0.22).delay(0.05)) { sectionOpacity = 1 }
        }
        .onAppear {
            section = section(for: style)
            visibleSection = section
            syncControls(from: style)
            syncEffects(state.document.backgroundEffects)
            uploads = WallpaperCatalog.userUploads()
            effectsOpacity = style.kind == .none ? 0 : 1
            effectsHeight = style.kind == .none ? 0 : effectsNaturalHeight
        }
        .onChange(of: style) { _, newStyle in
            section = section(for: newStyle)
            syncControls(from: newStyle)
        }
        .onChange(of: state.document.backgroundEffects) { _, fx in
            syncEffects(fx)
        }
    }

    // MARK: - Section tabs

    /// Color / Gradient / Wallpaper switcher: one accent pill that slides between
    /// equal segments, nested concentric-flush inside a carved groove track.
    private var sectionTabs: some View {
        let segments = Section.allCases
        let height: CGFloat = 30
        let shape = RoundedRectangle(cornerRadius: Theme.radiusPill, style: .continuous)
        return GeometryReader { geo in
            let segW = geo.size.width / CGFloat(segments.count)
            let idx = segments.firstIndex(of: section) ?? 0
            let slide = CGFloat(idx) * segW
            ZStack(alignment: .leading) {
                // Resting labels (dim) under the sliding pill.
                sectionLabelRow(segments, segW: segW, height: height, color: Theme.textSecondary)

                shape
                    .fill(LinearGradient(colors: [Theme.accentText, Theme.accent],
                                         startPoint: .top, endPoint: .bottom))
                    .frame(width: segW, height: height)
                    .offset(x: slide)
                    .animation(Theme.panelSpring, value: section)

                // Ink labels shown only through the pill, so the color reveal
                // tracks the pill exactly — no time-based crossfade flash.
                sectionLabelRow(segments, segW: segW, height: height, color: Theme.accentInk)
                    .mask(
                        shape
                            .frame(width: segW, height: height)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .offset(x: slide)
                            .animation(Theme.panelSpring, value: section)
                    )

                // Transparent hit layer.
                HStack(spacing: 0) {
                    ForEach(segments) { seg in
                        Color.clear
                            .frame(width: segW, height: height)
                            .contentShape(Rectangle())
                            .onTapGesture { section = seg }
                            .accessibilityLabel(seg.rawValue)
                            .accessibilityAddTraits(section == seg ? [.isSelected] : [])
                    }
                }
            }
        }
        .frame(height: height)
        .background(shape.fill(Color.black.opacity(0.25)))
        .overlay(shape.stroke(Color.white.opacity(0.06), lineWidth: 0.5))
        .clipShape(shape)
    }

    private func sectionLabelRow(_ segments: [Section], segW: CGFloat, height: CGFloat, color: Color) -> some View {
        HStack(spacing: 0) {
            ForEach(segments) { seg in
                HStack(spacing: 4) {
                    Image(systemName: seg.icon).font(.system(size: 11, weight: .semibold))
                        .frame(width: 14)
                    Text(seg.rawValue).font(Theme.label(11.5, .semibold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                }
                .frame(width: segW, height: height)
            }
        }
        .foregroundStyle(color)
        .allowsHitTesting(false)
    }

    // MARK: - Color

    private static let solidPresets: [Color] = [
        .white,
        Color(white: 0.62),
        Color(red: 0.11, green: 0.12, blue: 0.15),
        Color(red: 0.91, green: 0.30, blue: 0.24),
        Color(red: 0.96, green: 0.55, blue: 0.22),
        Color(red: 0.97, green: 0.78, blue: 0.30),
        Color(red: 0.36, green: 0.72, blue: 0.45),
        Color(red: 0.27, green: 0.60, blue: 0.91),
        Color(red: 0.55, green: 0.42, blue: 0.85),
        Color(red: 0.91, green: 0.45, blue: 0.66)
    ]

    private let solidColumns = [GridItem(.adaptive(minimum: 32), spacing: 10)]

    private var colorSection: some View {
        LazyVGrid(columns: solidColumns, alignment: .leading, spacing: 10) {
            swatchBead(selected: style.kind == .none) {
                Circle().fill(Color.black.opacity(0.3))
                    .overlay(
                        Image(systemName: "circle.slash").font(.system(size: 11))
                            .foregroundStyle(Theme.textTertiary)
                    )
            } action: { commit(.none) }

            ForEach(Array(Self.solidPresets.enumerated()), id: \.offset) { _, color in
                swatchBead(selected: isSolidSelected(color)) {
                    Circle().fill(color)
                } action: {
                    solid = color
                    commit(.solidColor(NSColor(color).cgColor))
                }
            }

            // Wildcard well: a rainbow-filled GlassColorWell — same component
            // and size as the gradient pickers — that opens the system picker.
            GlassColorWell(
                selection: $solid,
                label: "Custom color",
                fill: AnyShapeStyle(AngularGradient(colors: [
                    .red, .orange, .yellow, .green, .cyan, .blue, .purple, .pink, .red
                ], center: .center))
            )
            .onChange(of: solid) { _, _ in
                guard !isSyncingControls else { return }
                commit(.solidColor(NSColor(solid).cgColor))
            }
            // Stable identity: the lazy grid would otherwise recreate the well's
            // host on the post-commit re-render, severing its NSColorPanel link
            // so it only opens once.
            .id("customColorWell")
        }
    }

    /// 28pt round glass swatch sharing the bead vocabulary: active wears the
    /// vermilion ring and lifts.
    private func swatchBead<S: View>(
        selected: Bool,
        @ViewBuilder swatch: () -> S,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            beadFace(selected: selected, swatch: swatch)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? [.isSelected] : [])
    }

    private func beadFace<S: View>(
        selected: Bool,
        @ViewBuilder swatch: () -> S
    ) -> some View {
        swatch()
            .frame(width: 28, height: 28)
            .clipShape(Circle())
            .overlay(
                Circle().fill(
                    RadialGradient(colors: [.white.opacity(0.4), .clear],
                                   center: .init(x: 0.32, y: 0.22),
                                   startRadius: 0, endRadius: 12)
                )
            )
            .overlay(
                Circle().stroke(selected ? Theme.accent : Color.white.opacity(0.18),
                                lineWidth: selected ? 2 : 1)
            )
            .shadow(color: .black.opacity(0.3), radius: 2, y: 1)
            .scaleEffect(selected ? 1.1 : 1)
            .contentShape(Circle())
            .animation(.spring(duration: 0.25), value: selected)
    }

    private func isSolidSelected(_ color: Color) -> Bool {
        guard case .solidColor(let cg) = style else { return false }
        return cgColorsEqual(NSColor(color).cgColor, cg)
    }

    private func cgColorsEqual(_ a: CGColor, _ b: CGColor) -> Bool {
        guard let na = NSColor(cgColor: a)?.usingColorSpace(.sRGB),
              let nb = NSColor(cgColor: b)?.usingColorSpace(.sRGB) else { return false }
        return abs(na.redComponent - nb.redComponent) < 0.02
            && abs(na.greenComponent - nb.greenComponent) < 0.02
            && abs(na.blueComponent - nb.blueComponent) < 0.02
            && abs(na.alphaComponent - nb.alphaComponent) < 0.02
    }

    // MARK: - Gradient

    private var gradientSection: some View {
        VStack(alignment: .leading, spacing: Theme.panelRowSpacing) {
            HStack(spacing: 12) {
                bead(.gradient, selected: style.kind == .gradient) { applyGradient() }
                bead(.dynamic, selected: style.kind == .dynamic) { commit(.dynamic) }
                Spacer(minLength: 0)
            }
            if style.kind == .dynamic {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Image(systemName: "sparkles").font(.system(size: 10))
                    Text("Colors sampled from your screenshot")
                        .font(Theme.label(11.5)).lineSpacing(1)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .foregroundStyle(Theme.textTertiary)
                .padding(.top, 2)
            } else if style.kind == .gradient {
                HStack(spacing: 10) {
                    InspectorRowLabel(text: "Colors")
                    GlassColorWell(selection: $gradientStart, label: "Gradient start")
                        .onChange(of: gradientStart) { _, _ in
                            guard !isSyncingControls else { return }
                            applyGradient()
                        }
                    GlassColorWell(selection: $gradientEnd, label: "Gradient end")
                        .onChange(of: gradientEnd) { _, _ in
                            guard !isSyncingControls else { return }
                            applyGradient()
                        }
                }
                HStack(spacing: 10) {
                    InspectorRowLabel(text: "Angle")
                    GlassSlider(
                        value: Binding(
                            get: { gradientAngle },
                            set: { gradientAngle = $0; applyGradient() }
                        ),
                        range: 0...360,
                        accessibilityLabel: "Gradient angle",
                        accessibilityValue: { "\(Int($0.rounded())) degrees" }
                    )
                    InspectorValueLabel(text: "\(Int(gradientAngle))", suffix: "°")
                }
            }
            if !gradientWallpapers.isEmpty {
                wallpaperHeader("Presets")
                LazyVGrid(columns: wallpaperColumns, spacing: 8) {
                    ForEach(gradientWallpapers) { wallpaperTile($0) }
                }
            }
        }
    }

    private var gradientWallpapers: [Wallpaper] {
        WallpaperCatalog.bundledGroups().first { $0.category == "gradient" }?.items ?? []
    }

    /// Segment for a style; gradient-category wallpapers live under Gradient, not Wallpaper.
    private func section(for style: BackgroundStyle) -> Section {
        if case .image(let ref) = style, WallpaperCatalog.category(of: ref) == "gradient" {
            return .gradient
        }
        return Section(style.kind)
    }

    // MARK: - Wallpaper

    private let wallpaperColumns = [GridItem(.adaptive(minimum: 72), spacing: 8)]

    private var wallpaperSection: some View {
        VStack(alignment: .leading, spacing: Theme.panelRowSpacing) {
            ForEach(WallpaperCatalog.bundledGroups().filter { $0.category != "gradient" }, id: \.category) { group in
                wallpaperHeader(group.category.capitalized)
                LazyVGrid(columns: wallpaperColumns, spacing: 8) {
                    ForEach(group.items) { wallpaperTile($0) }
                }
            }
            wallpaperHeader("Your uploads")
            LazyVGrid(columns: wallpaperColumns, spacing: 8) {
                uploadTile
                ForEach(uploads) { wallpaperTile($0) }
            }
        }
    }

    private func wallpaperHeader(_ text: String) -> some View {
        Text(text.uppercased())
            .font(Theme.label(10)).foregroundStyle(Theme.textTertiary)
            .padding(.top, 2)
    }

    private func wallpaperTile(_ wallpaper: Wallpaper) -> some View {
        let selected = style == .image(wallpaper.ref)
        return Button {
            commit(.image(wallpaper.ref))
        } label: {
            WallpaperThumbnail(ref: wallpaper.ref)
                .aspectRatio(16.0 / 9.0, contentMode: .fill)
                .frame(height: 44)
                .clipShape(RoundedRectangle(cornerRadius: 7))
                .overlay(
                    RoundedRectangle(cornerRadius: 7)
                        .stroke(selected ? Theme.accent : Color.white.opacity(0.18),
                                lineWidth: selected ? 2 : 1)
                )
                .contentShape(RoundedRectangle(cornerRadius: 7))
        }
        .buttonStyle(.plain)
        .help(wallpaper.displayName)
        .accessibilityLabel(wallpaper.displayName)
        .accessibilityAddTraits(selected ? [.isSelected] : [])
    }

    private var uploadTile: some View {
        Button(action: pickUpload) {
            RoundedRectangle(cornerRadius: 7)
                .fill(Color.black.opacity(0.25))
                .frame(height: 44)
                .overlay(
                    Image(systemName: "plus")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(Theme.textSecondary)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 7)
                        .stroke(Color.white.opacity(0.18), style: StrokeStyle(lineWidth: 1, dash: [3]))
                )
        }
        .buttonStyle(.plain)
        .help("Upload an image")
        .accessibilityLabel("Upload an image")
    }

    private func pickUpload() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        guard let ref = try? WallpaperCatalog.importUpload(from: url) else { return }
        uploads = WallpaperCatalog.userUploads()
        commit(.image(ref))
    }

    // MARK: - Effects

    private var effects: some View {
        VStack(alignment: .leading, spacing: Theme.panelRowSpacing) {
            Rectangle().fill(Theme.hairline).frame(height: 1).padding(.vertical, 2)
            HStack(spacing: 10) {
                InspectorRowLabel(text: "Blur")
                GlassSlider(
                    value: Binding(get: { blur }, set: { blur = $0; commitEffects() }),
                    range: 0...Double(BackgroundEffects.maximumBlurRadius),
                    accessibilityLabel: "Background blur",
                    accessibilityValue: { "\(Int($0.rounded())) pixels" }
                )
                InspectorValueLabel(text: "\(Int(blur.rounded()))", suffix: "px")
            }
            HStack(spacing: 10) {
                InspectorRowLabel(text: "Noise")
                GlassSlider(
                    value: Binding(get: { noise }, set: { noise = $0; commitEffects() }),
                    range: 0...Double(BackgroundEffects.maximumNoiseOpacity * 100),
                    accessibilityLabel: "Background noise",
                    accessibilityValue: { "\(Int($0.rounded())) percent" }
                )
                InspectorValueLabel(text: "\(Int(noise))", suffix: "%")
            }
        }
    }

    // MARK: - Tiles

    /// Round glass bead matching the color-well vocabulary: active wears a
    /// vermilion ring and lifts.
    private func bead(_ kind: BackgroundStyle.Kind, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            tileSwatch(kind)
                .frame(width: 36, height: 36)
                .clipShape(Circle())
                .overlay(
                    Circle().fill(
                        RadialGradient(colors: [.white.opacity(0.4), .clear],
                                       center: .init(x: 0.32, y: 0.22),
                                       startRadius: 0, endRadius: 16)
                    )
                )
                .overlay(
                    Circle().stroke(selected ? Theme.accent : Color.white.opacity(0.18),
                                    lineWidth: selected ? 2 : 1)
                )
                .shadow(color: .black.opacity(0.3), radius: 2, y: 1)
                .scaleEffect(selected ? 1.08 : 1)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .animation(.spring(duration: 0.25), value: selected)
        .help(tileName(kind))
        .accessibilityLabel(tileName(kind))
        .accessibilityAddTraits(selected ? [.isSelected] : [])
    }

    @ViewBuilder
    private func tileSwatch(_ kind: BackgroundStyle.Kind) -> some View {
        switch kind {
        case .none:
            Circle().fill(Color.black.opacity(0.3))
                .overlay(
                    Image(systemName: "circle.slash").font(.system(size: 13))
                        .foregroundStyle(Theme.textTertiary)
                )
        case .solid:
            Circle().fill(solid)
        case .gradient:
            Circle().fill(
                LinearGradient(colors: [gradientStart, gradientEnd],
                               startPoint: .topLeading, endPoint: .bottomTrailing)
            )
        case .dynamic:
            Circle().fill(
                AngularGradient(colors: [
                    Color(red: 0.95, green: 0.35, blue: 0.45),
                    Color(red: 0.45, green: 0.45, blue: 0.95),
                    Color(red: 0.35, green: 0.85, blue: 0.75),
                    Color(red: 0.95, green: 0.35, blue: 0.45)
                ], center: .center)
            )
            .overlay(
                Image(systemName: "sparkles").font(.system(size: 12))
                    .foregroundStyle(.white.opacity(0.9))
            )
        case .wallpaper:
            Circle().fill(Color.black.opacity(0.3))
                .overlay(
                    Image(systemName: "photo").font(.system(size: 13))
                        .foregroundStyle(Theme.textTertiary)
                )
        }
    }

    private func tileName(_ kind: BackgroundStyle.Kind) -> String {
        switch kind {
        case .none: return "None"
        case .solid: return "Solid"
        case .gradient: return "Gradient"
        case .dynamic: return "Auto"
        case .wallpaper: return "Wallpaper"
        }
    }

    // MARK: - Commit / sync

    private func applyGradient() {
        commit(.gradient(
            start: NSColor(gradientStart).cgColor,
            end: NSColor(gradientEnd).cgColor,
            angleDegrees: CGFloat(gradientAngle)
        ))
    }

    private func commit(_ next: BackgroundStyle) {
        guard next != style else { return }
        state.performCommand(SetBackgroundCommand(from: style, to: next))
    }

    private func syncControls(from style: BackgroundStyle) {
        isSyncingControls = true
        defer { Task { @MainActor in isSyncingControls = false } }
        switch style {
        case .none, .dynamic, .image:
            break
        case .solidColor(let color):
            solid = Color(cgColor: color)
        case .gradient(let start, let end, let angle):
            gradientStart = Color(cgColor: start)
            gradientEnd = Color(cgColor: end)
            gradientAngle = Double(angle)
        }
    }

    private func commitEffects() {
        guard !isSyncingEffects else { return }
        let from = state.document.backgroundEffects
        let to = BackgroundEffects(
            blurRadius: CGFloat(blur),
            noiseOpacity: CGFloat(noise / 100)
        ).clamped
        guard to != from else { return }
        state.performCommand(SetBackgroundEffectsCommand(from: from, to: to))
    }

    private func syncEffects(_ fx: BackgroundEffects) {
        let nextBlur = Double(fx.clamped.blurRadius)
        let nextNoise = Double(fx.noiseOpacity * 100)
        guard blur != nextBlur || noise != nextNoise else { return }
        isSyncingEffects = true
        defer { Task { @MainActor in isSyncingEffects = false } }
        blur = nextBlur
        noise = nextNoise
    }
}

/// Async-loading wallpaper thumbnail backed by `WallpaperImageCache`.
private struct WallpaperThumbnail: View {
    let ref: WallpaperRef
    @State private var image: CGImage?

    var body: some View {
        Group {
            if let image {
                Image(decorative: image, scale: 1)
                    .resizable()
            } else {
                Rectangle().fill(Color.black.opacity(0.25))
            }
        }
        .task(id: ref.key) {
            let loaded = await Task.detached(priority: .userInitiated) {
                WallpaperImageCache.shared.thumbnail(for: ref, maxPixel: 240)
            }.value
            await MainActor.run { image = loaded }
        }
    }
}
