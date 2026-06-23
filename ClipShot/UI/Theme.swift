import AppKit
import SwiftUI

// MARK: - Design tokens — "Drafting Room"
//
// Warm graphite chrome around a workbench stage; a single vermilion accent spent
// only on selection, focus, and the primary action. Every numeric readout is
// monospaced. The captured image owns the contrast budget; the UI recedes.

enum Theme {

    // MARK: Surfaces (warm graphite)
    static let canvas        = Color(red: 0.075, green: 0.067, blue: 0.059)   // #131110 stage
    static let surface       = Color(red: 0.114, green: 0.102, blue: 0.090)   // #1D1A17 panels/bars
    static let surfaceHover  = Color(red: 0.157, green: 0.141, blue: 0.125)   // #282420 hover tint
    static let inputFill     = Color(red: 0.137, green: 0.122, blue: 0.106)   // #231F1B inset fields
    static let stageWell     = Color(red: 0.059, green: 0.051, blue: 0.043)   // #0F0D0B behind dot grid

    // MARK: Lines & shadow
    static let hairline       = Color.white.opacity(0.07)
    static let hairlineStrong = Color.white.opacity(0.14)
    static let floatShadow    = Color.black.opacity(0.5)
    static let stageDot       = Color.white.opacity(0.085)
    static let stageGridLine  = Color.white.opacity(0.05)

    // MARK: Ink (warm white, contrast-checked on `surface`)
    static let textPrimary   = Color(red: 0.961, green: 0.945, blue: 0.918)   // #F5F1EA ~15:1
    static let textSecondary = Color(red: 0.690, green: 0.655, blue: 0.604)   // #B0A79A ~7:1
    static let textTertiary  = Color(red: 0.553, green: 0.518, blue: 0.471)   // #8D8478 ~4.6:1

    // MARK: Accent — vermilion, the registration-mark color
    static let accent        = Color(red: 1.0, green: 0.361, blue: 0.220)     // #FF5C38
    static let accentText    = Color(red: 1.0, green: 0.557, blue: 0.420)     // #FF8E6B on dark ~7:1
    static let accentDim     = Color(red: 1.0, green: 0.361, blue: 0.220).opacity(0.14)
    /// Destructive hover tint (delete actions).
    static let danger        = Color(red: 1.0, green: 0.357, blue: 0.310)     // #FF5B4F
    static let accentFocus   = Color(red: 1.0, green: 0.361, blue: 0.220).opacity(0.55)
    static let accentInk     = Color(red: 0.173, green: 0.055, blue: 0.020)   // ink on solid accent

    /// AppKit/CoreAnimation consumers (selection halo, drag handles).
    static let accentCG = CGColor(red: 1.0, green: 0.361, blue: 0.220, alpha: 1)
    static let stageCG  = CGColor(red: 0.075, green: 0.067, blue: 0.059, alpha: 1)

    // MARK: Glass
    /// Warm tint mixed into every Liquid Glass panel so the floating chrome stays
    /// in the graphite family instead of going system-gray.
    // Strong enough that text stays readable when the white artboard slides
    // underneath the glass; weak enough that color still refracts through.
    static let glassTint = Color(red: 0.114, green: 0.102, blue: 0.090).opacity(0.4)

    // MARK: Geometry
    static let radiusControl: CGFloat = 7
    static let radiusPill: CGFloat = 11
    static let radiusPanel: CGFloat = 18
    /// Base inspector card width — the floor; the live width scales with the window.
    static let inspectorWidth: CGFloat = 272
    /// Inspector card width for a given window width: roughly proportional
    /// (~28% of the window) so the panel doesn't read as a sliver on large
    /// windows, floored at the base width and capped so cards never balloon.
    static func inspectorWidth(forWindowWidth windowWidth: CGFloat) -> CGFloat {
        min(max(inspectorWidth, windowWidth * 0.28), 460)
    }
    static let chromeMargin: CGFloat = 14
    /// Custom titlebar strip: the stoplight row with the app name centered on it.
    static let titleStripHeight: CGFloat = 28
    /// Floating control bar below the titlebar strip.
    static let topBarHeight: CGFloat = 48
    /// The floating dock's bar height (used by layout and canvas-fit occlusion).
    static let dockHeight: CGFloat = 52
    /// Vertical chrome the canvas fit must stay clear of: titlebar strip and
    /// bar/dock plus the matching margin that floats each off its edge.
    static var topChromeHeight: CGFloat { titleStripHeight + chromeMargin + topBarHeight }
    static var bottomChromeHeight: CGFloat { dockHeight + chromeMargin }
    /// Inspector edge treatment, referenced to the chrome rather than the
    /// window: cards stay fully transparent within the clear depth of the
    /// nearest chrome line (top bar below, dock line above), then dissolve in
    /// across the fade band. The bottom inset adds `bottomChromeHeight` so its
    /// gap reads against the dock line instead of the window edge.
    /// Breathing gap the initial canvas fit leaves inside the chrome lines.
    /// The inspector's fade edges anchor to the same offset, so cards stay
    /// fully opaque down to the image's exact vertical extent.
    static let canvasFitMargin: CGFloat = 16
    /// Cards are fully opaque at the image edge and dissolve outward across
    /// `scrollFadeBand`, past the chrome line. The rest position starts
    /// content at the image top, so on load the first card is crisp with no
    /// fade; the bottom band mirrors it exactly about the image's extent.
    static let scrollFadeBand: CGFloat = 48
    /// The band is deeper than the fit margin, so the inspector frame must
    /// extend this far above the top chrome line for the full band to fit
    /// while still going fully opaque exactly at the image top.
    static var scrollFadeOverhang: CGFloat { scrollFadeBand - canvasFitMargin }
    static var scrollFadeTopInset: CGFloat { scrollFadeBand }
    static var scrollFadeBottomInset: CGFloat { bottomChromeHeight + canvasFitMargin }
    /// Distance from the window's right edge to the visible left edge of the
    /// inspector cards (card width + the near 16pt scroll gutter + margin).
    /// The far gutter is excluded — measuring to the wrapper edge instead of
    /// the visible cards left the image reading off-center. The canvas fit and
    /// the dock both center in the space left of this, so the image's gap to
    /// the cards exactly matches its gap to the window edge.
    static var rightChromeWidth: CGFloat { rightChromeWidth(forInspector: inspectorWidth) }
    /// Same measurement for a live (window-proportional) inspector width.
    static func rightChromeWidth(forInspector inspectorWidth: CGFloat) -> CGFloat {
        inspectorWidth + panelInset + chromeMargin
    }

    // MARK: Motion
    /// Shared spring for chrome panels entering and leaving the stage; a touch
    /// underdamped so panels settle with a soft, liquid overshoot.
    static let panelSpring: Animation = .spring(response: 0.45, dampingFraction: 0.78)

    // MARK: Inspector rhythm — one spacing scale shared by every glass panel.
    /// Gap between labelled subsections inside a card.
    static let panelSectionSpacing: CGFloat = 16
    /// Gap between a section heading and its first control.
    static let panelHeaderSpacing: CGFloat = 7
    /// Gap between control rows within one subsection.
    static let panelRowSpacing: CGFloat = 10
    /// Interior inset of a glass panel (horizontal and bottom edges).
    static let panelInset: CGFloat = 16
    /// Top inset; tighter because the title's cap height carries its own headroom.
    static let panelInsetTop: CGFloat = 13
    /// Gap between stacked inspector cards; the glass edge amplifies it visually.
    static let cardGap: CGFloat = 12
    /// Horizontal inset for glass bars (dock), whose rounded ends add optical room.
    static let barInset: CGFloat = 12

    // MARK: Type — SF Pro for labels, SF Mono for every measured value
    static func title(_ size: CGFloat = 14, _ weight: Font.Weight = .semibold) -> Font {
        .system(size: size, weight: weight, design: .default)
    }
    static func section(_ size: CGFloat = 11.5, _ weight: Font.Weight = .semibold) -> Font {
        .system(size: size, weight: weight, design: .default)
    }
    static func label(_ size: CGFloat = 12, _ weight: Font.Weight = .medium) -> Font {
        .system(size: size, weight: weight, design: .default)
    }
    static func mono(_ size: CGFloat = 11.5, _ weight: Font.Weight = .medium) -> Font {
        .system(size: size, weight: weight, design: .monospaced)
    }
}

// MARK: - Stage material

/// The workbench: a deep well with a fixed dot grid and a soft vignette. Sits behind
/// the canvas scroll view (which is transparent) so the stage reads as one surface.
struct StageBackdrop: View {
    var body: some View {
        ZStack {
            Theme.canvas
            Canvas { context, size in
                let spacing: CGFloat = 22
                let dot: CGFloat = 1.5
                // Major drafting lines every 5 dot cells: sharp structure that the
                // glass panels visibly refract (the blur needs detail to act on).
                let major = spacing * 5
                var gx = major
                while gx < size.width {
                    context.fill(
                        Path(CGRect(x: gx - 0.25, y: 0, width: 0.5, height: size.height)),
                        with: .color(Theme.stageGridLine)
                    )
                    gx += major
                }
                var gy = major
                while gy < size.height {
                    context.fill(
                        Path(CGRect(x: 0, y: gy - 0.25, width: size.width, height: 0.5)),
                        with: .color(Theme.stageGridLine)
                    )
                    gy += major
                }
                var x = spacing / 2
                while x < size.width {
                    var y = spacing / 2
                    while y < size.height {
                        let rect = CGRect(x: x - dot / 2, y: y - dot / 2, width: dot, height: dot)
                        context.fill(Path(ellipseIn: rect), with: .color(Theme.stageDot))
                        y += spacing
                    }
                    x += spacing
                }
            }
            // Vignette keeps attention pooled at the artboard in the middle.
            RadialGradient(
                colors: [.clear, Theme.stageWell.opacity(0.7)],
                center: .center, startRadius: 200, endRadius: 900
            )
        }
        .drawingGroup()
        .accessibilityHidden(true)
    }
}

/// Ambient bleed: the capture's own palette diffused across the whole stage as
/// huge soft glows. Sits between the dot grid and everything else, so the color
/// reaches the window edges and refracts up through every glass panel.
struct AmbientGlowView: View {
    /// Mesh-order palette (3×3, top-left → bottom-right). Fewer colors degrade
    /// gracefully — each blob indexes with wraparound.
    let colors: [Color]
    /// The card's on-screen frame (stage space). Blobs anchor to its edges so the
    /// light reads as spilling from the artboard, not the window. Null → full stage.
    var cardFrame: CGRect = .null

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width, h = geo.size.height
            // Anchor to the card's real frame when known, else the whole stage.
            let f = (cardFrame.isNull || cardFrame.isEmpty)
                ? CGRect(x: 0, y: 0, width: w, height: h) : cardFrame
            let d = max(w, h)
            let cr = d * 0.34, er = d * 0.32
            ZStack {
                // Each perimeter zone radiates its own edge color outward from the
                // card edge, so the light direction reads true (right edge → right
                // glow) and originates at the artboard, not the window corner.
                blob(0, x: f.minX, y: f.minY, r: cr)            // TL
                blob(1, x: f.midX, y: f.minY, r: er)            // top
                blob(2, x: f.maxX, y: f.minY, r: cr)            // TR
                blob(3, x: f.minX, y: f.midY, r: er)            // left
                blob(5, x: f.maxX, y: f.midY, r: er)            // right
                blob(6, x: f.minX, y: f.maxY, r: cr)            // BL
                blob(7, x: f.midX, y: f.maxY, r: er)            // bottom
                blob(8, x: f.maxX, y: f.maxY, r: cr)            // BR
                blob(4, x: f.midX, y: f.midY, r: d * 0.24)      // center
            }
            .blur(radius: 70)
            .saturation(1.1)
            .opacity(0.42)
        }
        .drawingGroup()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private func blob(_ index: Int, x: CGFloat, y: CGFloat, r: CGFloat) -> some View {
        if !colors.isEmpty {
            let color = colors[index % colors.count]
            Circle()
                .fill(
                    RadialGradient(colors: [color, color.opacity(0)],
                                   center: .center, startRadius: 0, endRadius: r)
                )
                .frame(width: r * 2, height: r * 2)
                .position(x: x, y: y)
        }
    }
}

/// Lightweight animated field of small warm glow motes drifting over the home
/// stage, atop a few huge faint warm blobs — one Canvas pass, GPU.
struct DriftField: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private struct Mark {
        var x, y, dx, dy, size: CGFloat
        var hue: Int
        var opacity, phase: CGFloat
    }

    private struct RNG: RandomNumberGenerator {
        var state: UInt64
        init(_ seed: UInt64) { state = seed != 0 ? seed : 0x9E37_79B9_7F4A_7C15 }
        mutating func next() -> UInt64 {
            state ^= state << 13; state ^= state >> 7; state ^= state << 17
            return state
        }
    }

    // Warm only — vermilion, amber, rose.
    private static let palette: [Color] = [
        Theme.accent,
        Color(red: 1.0, green: 0.64, blue: 0.34),
        Color(red: 1.0, green: 0.47, blue: 0.43)
    ]

    private static let marks: [Mark] = makeMarks()
    private static let blobs: [Mark] = makeBlobs()

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: reduceMotion)) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate
            Canvas { ctx, size in
                for b in Self.blobs { Self.drawBlob(b, t: t, size: size, into: &ctx) }
                for m in Self.marks { Self.drawMark(m, t: t, size: size, into: &ctx) }
            }
        }
        .drawingGroup()
        .blendMode(.plusLighter)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private static func makeMarks() -> [Mark] {
        var rng = RNG(0xC119_5A07)
        return (0..<40).map { _ in
            Mark(
                x: .random(in: 0...1, using: &rng),
                y: .random(in: 0...1, using: &rng),
                dx: .random(in: -0.011...0.011, using: &rng),
                dy: .random(in: -0.011...0.011, using: &rng),
                size: .random(in: 8...22, using: &rng),
                hue: Int.random(in: 0..<palette.count, using: &rng),
                opacity: .random(in: 0.06...0.17, using: &rng),
                phase: .random(in: 0...(.pi * 2), using: &rng)
            )
        }
    }

    private static func makeBlobs() -> [Mark] {
        var rng = RNG(0x5EED_9B10)
        return (0..<4).map { _ in
            Mark(
                x: .random(in: 0.2...0.8, using: &rng),
                y: .random(in: 0.2...0.8, using: &rng),
                // dx/dy are oscillation amplitudes (fraction of size), not velocity.
                dx: .random(in: 0.04...0.08, using: &rng),
                dy: .random(in: 0.04...0.08, using: &rng),
                size: .random(in: 0.30...0.46, using: &rng),
                hue: Int.random(in: 0..<palette.count, using: &rng),
                opacity: .random(in: 0.05...0.09, using: &rng),
                phase: .random(in: 0...(.pi * 2), using: &rng)
            )
        }
    }

    private static func wrap(_ v: CGFloat) -> CGFloat {
        let w = v.truncatingRemainder(dividingBy: 1); return w < 0 ? w + 1 : w
    }

    private static func drawMark(_ m: Mark, t: Double, size: CGSize, into ctx: inout GraphicsContext) {
        let fx = wrap(m.x + m.dx * CGFloat(t)), fy = wrap(m.y + m.dy * CGFloat(t))
        // Fade near edges so wraps don't pop.
        let edge: CGFloat = 0.07
        let ef = min(1, min(fx, 1 - fx) / edge) * min(1, min(fy, 1 - fy) / edge)
        let breathe = 0.7 + 0.3 * CGFloat(sin(t * 0.22 + Double(m.phase)))
        let p = CGPoint(x: fx * size.width, y: fy * size.height)
        let color = palette[m.hue].opacity(m.opacity * max(0, ef) * breathe)
        let a = m.size
        let rect = CGRect(x: p.x - a, y: p.y - a, width: a * 2, height: a * 2)
        ctx.fill(Path(ellipseIn: rect),
                 with: .radialGradient(Gradient(colors: [color, color.opacity(0)]),
                                       center: p, startRadius: 0, endRadius: a))
    }

    private static func drawBlob(_ m: Mark, t: Double, size: CGSize, into ctx: inout GraphicsContext) {
        // Slow Lissajous drift around the base point — bounded, never wraps.
        let sx = CGFloat(sin(t * 0.05 + Double(m.phase)))
        let sy = CGFloat(sin(t * 0.04 + Double(m.phase) * 1.7 + 1.0))
        let cx = (m.x + m.dx * sx) * size.width
        let cy = (m.y + m.dy * sy) * size.height
        let r = m.size * max(size.width, size.height)
        let breathe = 0.85 + 0.15 * CGFloat(sin(t * 0.12 + Double(m.phase)))
        let color = palette[m.hue].opacity(m.opacity * breathe)
        let center = CGPoint(x: cx, y: cy)
        let rect = CGRect(x: cx - r, y: cy - r, width: r * 2, height: r * 2)
        ctx.fill(Path(ellipseIn: rect),
                 with: .radialGradient(Gradient(colors: [color, color.opacity(0)]),
                                       center: center, startRadius: 0, endRadius: r))
    }
}

/// Registration ticks marking the four corners of the stage — the drafting-table frame.
struct StageCornerTicks: View {
    private let arm: CGFloat = 14
    private let inset: CGFloat = 10

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width, h = geo.size.height
            Path { p in
                for (cx, cy, sx, sy) in [
                    (inset, inset, 1.0, 1.0), (w - inset, inset, -1.0, 1.0),
                    (inset, h - inset, 1.0, -1.0), (w - inset, h - inset, -1.0, -1.0)
                ] {
                    p.move(to: CGPoint(x: cx + CGFloat(sx) * arm, y: cy))
                    p.addLine(to: CGPoint(x: cx, y: cy))
                    p.addLine(to: CGPoint(x: cx, y: cy + CGFloat(sy) * arm))
                }
            }
            .stroke(Theme.hairlineStrong, lineWidth: 1)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// The brand mark: the compiled app icon itself, scaled to chrome size.
/// Used by the top bar wordmark and menu popover.
struct BrandMarkGlyph: View {
    var body: some View {
        Image(nsImage: NSApp.applicationIconImage)
            .resizable()
            .scaledToFit()
            .accessibilityHidden(true)
    }
}

// MARK: - Shared text roles

/// Tracked-uppercase section label; smaller and dimmer than row labels on purpose.
struct SectionLabel: View {
    let text: String
    var body: some View {
        Text(text.uppercased())
            .font(Theme.section(10, .semibold))
            .tracking(0.9)
            .foregroundStyle(Theme.textTertiary)
    }
}

/// One labelled subsection of a glass panel: tracked heading, optional trailing
/// accessory, and rows — all at the shared inspector rhythm.
struct PanelSection<Accessory: View, Content: View>: View {
    let title: String
    @ViewBuilder var accessory: () -> Accessory
    @ViewBuilder var content: () -> Content

    init(
        _ title: String,
        @ViewBuilder accessory: @escaping () -> Accessory = { EmptyView() },
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.title = title
        self.accessory = accessory
        self.content = content
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.panelHeaderSpacing) {
            HStack(spacing: 8) {
                SectionLabel(text: title)
                Spacer(minLength: 8)
                // Zero height so a tall accessory can't shift the heading (see GlassCard).
                accessory()
                    .frame(height: 0)
            }
            VStack(alignment: .leading, spacing: Theme.panelRowSpacing) {
                content()
            }
        }
    }
}

/// Inspector row label (left column) — shared by every tool panel. Pass
/// `nested: true` for rows that sit *under* a section heading, so they read as
/// subordinate (smaller, dimmer) instead of competing with the heading.
struct InspectorRowLabel: View {
    let text: String
    var nested: Bool = false
    var body: some View {
        Text(text)
            .font(nested ? Theme.label(11, .medium) : Theme.label())
            .foregroundStyle(nested ? Theme.textTertiary : Theme.textSecondary)
            .frame(width: 56, alignment: .leading)
    }
}

/// Inspector numeric readout (right column) — always monospaced, always aligned.
/// Units ("%", "°") render in a fixed gutter so digits share one column everywhere.
struct InspectorValueLabel: View {
    let text: String
    var suffix: String = ""
    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 1) {
            Text(text)
                .font(Theme.mono(11.5, .semibold))
                .foregroundStyle(Theme.textPrimary)
                .frame(width: 36, alignment: .trailing)
            Text(suffix)
                .font(Theme.mono(9.5, .medium))
                .foregroundStyle(Theme.textTertiary)
                .lineLimit(1)
                .fixedSize()
                .frame(width: 14, alignment: .leading)
        }
    }
}

/// Keycap glyph for shortcut hints ("⌃", "⇧", "5").
struct Keycap: View {
    let text: String
    var glass: Bool = false

    @ViewBuilder
    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 5, style: .continuous)
        let label = Text(text)
            .font(Theme.mono(11, .semibold))
            .foregroundStyle(Theme.textSecondary)
            .frame(minWidth: 22)
            .frame(height: 22)
            .padding(.horizontal, 3)
        if glass, #available(macOS 26.0, *) {
            label.glassEffect(.regular.tint(Theme.glassTint), in: shape)
        } else {
            label
                .background(shape.fill(Theme.inputFill))
                .overlay(shape.stroke(Theme.hairlineStrong, lineWidth: 1))
        }
    }
}

// MARK: - Layout environment

/// Live inspector card width, set once at the editor root from the window size
/// so every card (and the column that holds them) scales with the window.
private struct InspectorWidthKey: EnvironmentKey {
    static let defaultValue: CGFloat = Theme.inspectorWidth
}

extension EnvironmentValues {
    var inspectorWidth: CGFloat {
        get { self[InspectorWidthKey.self] }
        set { self[InspectorWidthKey.self] = newValue }
    }
}

// MARK: - Containers

/// Liquid Glass panel: the one material for every piece of floating chrome.
/// Real `glassEffect` with a warm graphite tint on macOS 26 so panels lens the
/// canvas running underneath; frosted material fallback on older systems.
struct GlassPanel: ViewModifier {
    var cornerRadius: CGFloat = Theme.radiusPanel

    @ViewBuilder
    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        if #available(macOS 26.0, *) {
            content
                .glassEffect(.regular.tint(Theme.glassTint), in: shape)
        } else {
            content
                .background(.ultraThinMaterial, in: shape)
                .background(shape.fill(Theme.glassTint))
                .overlay(
                    shape.strokeBorder(
                        LinearGradient(
                            colors: [Color.white.opacity(0.22), Color.white.opacity(0.04)],
                            startPoint: .top, endPoint: .bottom
                        ),
                        lineWidth: 1
                    )
                )
        }
    }
}

/// Floating plate: almost not there, and dissolving. A ghost of a fill and
/// outline ground the left end — where the brand tick and the start of the
/// title live — and the whole plate (shadow included) fades out toward the
/// right until it is simply gone. The shape never terminates in a visible
/// right edge, so the title can run long without ever reading as a box.
/// Reserved for the capture title.
struct FloatingGlassPanel: ViewModifier {
    var cornerRadius: CGFloat = Theme.radiusPanel
    var glow: Bool = false

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        content
            .background(
                ZStack {
                    shape.fill(Color.white.opacity(0.02))
                    shape.strokeBorder(
                        LinearGradient(
                            colors: [Color.white.opacity(0.07), Color.white.opacity(0.02)],
                            startPoint: .top, endPoint: .bottom
                        ),
                        lineWidth: 1
                    )
                    // Focus glow: an accent rim with a soft halo. Its own mask
                    // dies well before the plate's right corner — the rim never
                    // wraps around the end, so it reads as two rays trailing off
                    // to infinity rather than the edge of a box.
                    shape.strokeBorder(Theme.accent.opacity(0.5), lineWidth: 1)
                        .shadow(color: Theme.accent.opacity(0.55), radius: 9)
                        .mask(
                            LinearGradient(stops: [
                                .init(color: .black, location: 0),
                                .init(color: .black, location: 0.25),
                                .init(color: .black.opacity(0), location: 0.62)
                            ], startPoint: .leading, endPoint: .trailing)
                            .padding(-40)
                        )
                        .opacity(glow ? 1 : 0)
                }
                .compositingGroup()
                .shadow(color: Color.black.opacity(0.35), radius: 18, y: 8)
                // Dissolve: solid through the left third, gone before the right
                // edge. Negative padding widens the mask so the soft shadow
                // isn't clipped at the plate bounds.
                .mask(
                    LinearGradient(stops: [
                        .init(color: .black, location: 0),
                        .init(color: .black, location: 0.38),
                        .init(color: .black.opacity(0), location: 0.94)
                    ], startPoint: .leading, endPoint: .trailing)
                    .padding(-40)
                )
                .allowsHitTesting(false)
            )
            .animation(.easeInOut(duration: 0.22), value: glow)
    }
}

extension View {
    func glassPanel(cornerRadius: CGFloat = Theme.radiusPanel) -> some View {
        modifier(GlassPanel(cornerRadius: cornerRadius))
    }

    func floatingGlassPanel(cornerRadius: CGFloat = Theme.radiusPanel, glow: Bool = false) -> some View {
        modifier(FloatingGlassPanel(cornerRadius: cornerRadius, glow: glow))
    }

    /// Bottom command bar via `safeAreaBar` (macOS 26) so scrollable content can
    /// run underneath with the system's progressive edge treatment; plain overlay
    /// on older systems.
    @ViewBuilder
    func bottomDockBar<C: View>(@ViewBuilder content: @escaping () -> C) -> some View {
        if #available(macOS 26.0, *) {
            safeAreaBar(edge: .bottom) { content() }
        } else {
            overlay(alignment: .bottom) { content() }
        }
    }

    /// Soft scroll-edge effect: content blurs and fades out at the scroll bounds
    /// instead of hard-clipping at a divider line.
    @ViewBuilder
    func softVerticalScrollEdges() -> some View {
        if #available(macOS 26.0, *) {
            scrollEdgeEffectStyle(.soft, for: .vertical)
        } else {
            self
        }
    }

}

/// One floating inspector card: a glass panel with a title row and its controls.
/// The inspector is a loose column of these — every card always open, always in
/// the same place. No chevrons, no routing, no collapse state to manage.
struct GlassCard<Accessory: View, Content: View>: View {
    let title: String
    /// When false, renders only the card interior (title row + controls) with
    /// no glass chrome — for slots that draw one persistent glass surface
    /// around swappable interiors so the surface can resize smoothly.
    let glass: Bool
    @Environment(\.inspectorWidth) private var inspectorWidth
    @ViewBuilder var accessory: () -> Accessory
    @ViewBuilder var content: () -> Content

    init(
        _ title: String,
        glass: Bool = true,
        @ViewBuilder accessory: @escaping () -> Accessory = { EmptyView() },
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.title = title
        self.glass = glass
        self.accessory = accessory
        self.content = content
    }

    var body: some View {
        if glass {
            interior.glassPanel()
        } else {
            interior
        }
    }

    private var interior: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                SectionLabel(text: title)
                Spacer(minLength: 8)
                // Zero layout height: a tall accessory centers on the title's midline
                // instead of inflating the row, so headings align across cards.
                accessory()
                    .frame(height: 0)
            }
            .padding(.horizontal, Theme.panelInset)
            .padding(.top, Theme.panelInsetTop)
            .padding(.bottom, Theme.panelRowSpacing)

            content()
                .padding(.horizontal, Theme.panelInset)
                .padding(.bottom, Theme.panelInset)
        }
        .frame(width: inspectorWidth)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(title)
    }
}

/// Tool-pod button: icon that fills with the accent when its tool is engaged.
/// Lives inside the floating glass pod, so state is carried by the fill, not an
/// edge tick that would escape the glass shape.
struct ToolRailButton: View {
    let systemName: String
    let label: String
    let shortcut: String?
    let isActive: Bool
    var action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 14.5, weight: .medium))
                .foregroundStyle(isActive ? Theme.accentInk : (hovering ? Theme.textPrimary : Theme.textSecondary))
                .frame(width: 36, height: 36)
                .background(
                    ZStack {
                        RoundedRectangle(cornerRadius: Theme.radiusPill, style: .continuous)
                            .fill(Theme.surfaceHover)
                            .opacity(hovering && !isActive ? 1 : 0)
                        RoundedRectangle(cornerRadius: Theme.radiusPill, style: .continuous)
                            .fill(Theme.accent)
                            .scaleEffect(isActive ? 1 : 0.6)
                            .opacity(isActive ? 1 : 0)
                    }
                    .padding(3)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.12), value: hovering)
        .animation(.spring(response: 0.28, dampingFraction: 0.72), value: isActive)
        .help(shortcut.map { "\(label)  \($0)" } ?? label)
        .accessibilityLabel(label)
        .accessibilityAddTraits(isActive ? [.isSelected] : [])
    }
}

// MARK: - Controls

/// Glass slider: a carved groove with a luminous vermilion fill and a lens knob.
/// The fill stays lit (dimmer at rest, glowing under the hand) so the groove reads
/// as an instrument, not a progress bar.
struct GlassSlider: View {
    @Binding var value: Double
    var range: ClosedRange<Double>
    var accessibilityLabel: String
    var accessibilityValue: (Double) -> String = { "\(Int($0.rounded()))" }
    var onEditingChanged: (Bool) -> Void = { _ in }

    @State private var isEditing = false
    @State private var hovering = false
    // True while the cursor sits within grab range of the knob — i.e. a press
    // would pick the knob up rather than jump it. Drives the armed indicator.
    @State private var nearKnob = false
    // When a drag starts on/near the knob, grab it and track the finger's offset
    // so the value follows the drag instead of jumping to the press point.
    @State private var grabOffset: CGFloat? = nil

    private let trackHeight: CGFloat = 5
    private let knob: CGFloat = 15

    private var engaged: Bool { isEditing || hovering }
    private var armed: Bool { isEditing || nearKnob }

    var body: some View {
        // GeometryReader is intentional: knob offset arithmetic needs the numeric track width.
        GeometryReader { geo in
            let width = geo.size.width
            let span = range.upperBound - range.lowerBound
            let fraction = span > 0 ? (value - range.lowerBound) / span : 0
            let clamped = min(max(fraction, 0), 1)
            let knobX = CGFloat(clamped) * (width - knob) + knob / 2

            ZStack(alignment: .leading) {
                // Groove: carved into the glass, darker than the panel.
                Capsule()
                    .fill(Color.black.opacity(0.36))
                    .frame(height: trackHeight)
                    .overlay(
                        Capsule()
                            .stroke(Color.white.opacity(0.10), lineWidth: 0.5)
                            .blendMode(.plusLighter)
                            .mask(Capsule().padding(.top, trackHeight - 2))
                    )
                // Luminous fill: vermilion gradient, glows while engaged.
                Capsule()
                    .fill(
                        LinearGradient(
                            colors: [Theme.accent.opacity(engaged ? 1 : 0.62),
                                     Theme.accentText.opacity(engaged ? 1 : 0.62)],
                            startPoint: .leading, endPoint: .trailing
                        )
                    )
                    .frame(width: max(knobX, trackHeight), height: trackHeight)
                // Lens knob: a tiny glass bead with a top highlight.
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [Color.white, Theme.textPrimary.opacity(0.85)],
                            center: .init(x: 0.35, y: 0.25), startRadius: 0, endRadius: 10
                        )
                    )
                    .frame(width: knob, height: knob)
                    .overlay(Circle().stroke(Color.black.opacity(0.25), lineWidth: 0.5))
                    .shadow(color: .black.opacity(0.4), radius: 2, y: 1)
                    // Armed: a vermilion focus ring + accent halo so the knob
                    // reads as "live" the moment the cursor can pick it up.
                    .overlay(Circle().stroke(Theme.accent, lineWidth: armed ? (isEditing ? 3 : 2) : 0))
                    .shadow(color: Theme.accent.opacity(armed ? 0.6 : 0), radius: armed ? 6 : 0)
                    .scaleEffect(isEditing ? 1.18 : (armed ? 1.1 : 1))
                    .offset(x: knobX - knob / 2)
            }
            .frame(height: knob)
            .contentShape(Rectangle())
            // Direct drag instead of a hidden Slider: a hidden NSSlider also eats
            // scroll-wheel events, so scrolling the inspector would silently edit values.
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { gesture in
                        if !isEditing {
                            isEditing = true
                            onEditingChanged(true)
                            // Grab the knob if the press lands within a knob-width of it.
                            grabOffset = abs(gesture.startLocation.x - knobX) <= knob
                                ? knobX - gesture.startLocation.x
                                : nil
                        }
                        value = valueAt(x: gesture.location.x + (grabOffset ?? 0), width: width)
                    }
                    .onEnded { _ in
                        isEditing = false
                        grabOffset = nil
                        onEditingChanged(false)
                    }
            )
            .onContinuousHover { phase in
                switch phase {
                case .active(let location):
                    hovering = true
                    nearKnob = abs(location.x - knobX) <= knob
                case .ended:
                    hovering = false
                    nearKnob = false
                }
            }
            .animation(.easeOut(duration: 0.12), value: isEditing)
            .animation(.easeOut(duration: 0.12), value: hovering)
            .animation(.easeOut(duration: 0.12), value: nearKnob)
        }
        .frame(height: knob)
        .accessibilityElement()
        .accessibilityLabel(Text(accessibilityLabel))
        .accessibilityValue(Text(accessibilityValue(value)))
        .accessibilityAdjustableAction { direction in
            let step = (range.upperBound - range.lowerBound) / 20
            let next: Double
            switch direction {
            case .increment: next = min(range.upperBound, value + step)
            case .decrement: next = max(range.lowerBound, value - step)
            @unknown default: return
            }
            guard next != value else { return }
            onEditingChanged(true)
            value = next
            onEditingChanged(false)
        }
    }

    private func valueAt(x: CGFloat, width: CGFloat) -> Double {
        let usable = max(width - knob, 1)
        let fraction = min(max((x - knob / 2) / usable, 0), 1)
        return range.lowerBound + Double(fraction) * (range.upperBound - range.lowerBound)
    }
}

/// Glass toggle: a small carved capsule whose bead slides and ignites vermilion.
/// Replaces the system switch everywhere in the inspector.
struct GlassToggleStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        Button {
            // Drive the flip inside an explicit transaction: the bound state
            // often commits through a command that rebuilds the parent, which
            // swallows the implicit `.animation(value:)`.
            withAnimation(.spring(duration: 0.22)) {
                configuration.isOn.toggle()
            }
        } label: {
            // Two fills crossfade on opacity (gradients don't interpolate, so a
            // single swapped fill would snap); the vermilion ignites in step with
            // the sliding bead.
            ZStack {
                Capsule().fill(trackFill(false))
                Capsule().fill(trackFill(true)).opacity(configuration.isOn ? 1 : 0)
            }
                .overlay(Capsule().stroke(Color.white.opacity(configuration.isOn ? 0.28 : 0.08), lineWidth: 0.5))
                .overlay(alignment: configuration.isOn ? .trailing : .leading) {
                    Circle()
                        .fill(
                            RadialGradient(
                                colors: [Color.white, Theme.textPrimary.opacity(0.9)],
                                center: .init(x: 0.35, y: 0.25), startRadius: 0, endRadius: 9
                            )
                        )
                        .overlay(Circle().strokeBorder(
                            LinearGradient(colors: [.white.opacity(0.7), .black.opacity(0.18)],
                                           startPoint: .top, endPoint: .bottom), lineWidth: 0.5))
                        .frame(width: 13, height: 13)
                        .shadow(color: .black.opacity(0.4), radius: 1.5, y: 1)
                        .padding(2.5)
                }
                .frame(width: 34, height: 18)
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .animation(.spring(duration: 0.22), value: configuration.isOn)
        .accessibilityAddTraits(configuration.isOn ? [.isSelected] : [])
    }

    /// Recessed track: on wears a top-lit vermilion gradient, off a carved dark
    /// slot — both finished with an inner shadow so the bead reads as set into it.
    private func trackFill(_ isOn: Bool) -> some ShapeStyle {
        let colors: [Color] = isOn
            ? [Theme.accent, Theme.accentText]
            : [.black.opacity(0.46), .black.opacity(0.30)]
        return LinearGradient(colors: colors, startPoint: .top, endPoint: .bottom)
            .shadow(.inner(color: .black.opacity(isOn ? 0.35 : 0.45), radius: 2, y: 1))
    }
}

/// Circular color swatch with liquid-glass depth. Shared by every color orb so
/// all wells render consistently across the inspector. The color itself gains
/// volume — a sheen across the top, shade pooling below — plus a sharp specular
/// arc and a graded rim.
struct BeadFace<S: View>: View {
    let selected: Bool
    let diameter: CGFloat
    @ViewBuilder var swatch: () -> S

    var body: some View {
        liquid
            .overlay(Circle().stroke(selected ? Theme.accent : .clear, lineWidth: 2))
    }

    private var base: some View {
        swatch().frame(width: diameter, height: diameter).clipShape(Circle())
    }

    private var liquid: some View {
        base
            // Inner shadow pooling at the bottom edge: convex volume without
            // washing the face, so the color stays vivid through the center.
            .overlay(
                Circle().strokeBorder(
                    LinearGradient(colors: [.clear, .black.opacity(0.38)],
                                   startPoint: .top, endPoint: .bottom),
                    lineWidth: diameter * 0.16)
                    .blur(radius: diameter * 0.05)
                    .mask(Circle())
            )
            // Bright specular along the top edge — the glass catching light.
            .overlay(Circle().strokeBorder(
                LinearGradient(colors: [.white.opacity(0.8), .clear],
                               startPoint: .top, endPoint: .center), lineWidth: 1.2))
            // Thin graded definition rim, top-light to bottom-dark.
            .overlay(Circle().strokeBorder(
                LinearGradient(colors: [.white.opacity(0.3), .black.opacity(0.3)],
                               startPoint: .top, endPoint: .bottom), lineWidth: 0.75))
            .compositingGroup()
    }
}

/// Drives the shared `NSColorPanel` and forwards live color changes to a
/// binding. Avoids SwiftUI's `ColorPicker`, whose `NSColorWell` paints an
/// AppKit active-frame that bleeds through any opacity.
@MainActor
final class ColorPanelProxy: NSObject {
    var onChange: ((Color) -> Void)?

    func present(_ color: Color, supportsOpacity: Bool) {
        let panel = NSColorPanel.shared
        panel.showsAlpha = supportsOpacity
        panel.isContinuous = true
        panel.color = NSColor(color)
        panel.setTarget(self)
        panel.setAction(#selector(colorChanged(_:)))
        panel.orderFront(nil)
    }

    @objc private func colorChanged(_ sender: NSColorPanel) {
        onChange?(Color(nsColor: sender.color))
    }
}

/// Round liquid-glass color well: the `BeadFace` swatch is the whole control;
/// tapping it opens the system color panel. No `NSColorWell`, so nothing paints
/// an active ring around it.
struct GlassColorWell: View {
    @Binding var selection: Color
    var supportsOpacity: Bool = false
    var label: String = "Color"
    /// Optional fill override — e.g. a rainbow gradient to mark a wildcard
    /// "pick any color" well. Defaults to the current selection.
    var fill: AnyShapeStyle? = nil
    var diameter: CGFloat = 23
    @State private var hovering = false
    @State private var proxy = ColorPanelProxy()

    var body: some View {
        Button {
            proxy.onChange = { selection = $0 }
            proxy.present(selection, supportsOpacity: supportsOpacity)
        } label: {
            BeadFace(selected: false, diameter: diameter) {
                Circle().fill(fill ?? AnyShapeStyle(selection))
            }
            .overlay(Circle().stroke(Color.white.opacity(hovering ? 0.45 : 0), lineWidth: 1))
            .frame(width: diameter, height: diameter)
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .focusEffectDisabled()
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.12), value: hovering)
        .help(label)
        .accessibilityLabel(label)
    }
}

/// Square icon button for the floating tool palette (drawing modes).
struct ToolPaletteButton: View {
    let systemName: String
    let label: String
    let isActive: Bool
    var action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(isActive ? Theme.accentText : (hovering ? Theme.textPrimary : Theme.textSecondary))
                .frame(width: 34, height: 34)
                .background(
                    RoundedRectangle(cornerRadius: Theme.radiusControl, style: .continuous)
                        .fill(isActive ? Theme.accentDim : (hovering ? Theme.surfaceHover : .clear))
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.12), value: hovering)
        .help(label)
        .accessibilityLabel(label)
        .accessibilityAddTraits(isActive ? [.isSelected] : [])
    }
}

/// Compact icon button (undo/redo, panel close). Flat, hover tint only.
struct IconButton: View {
    let systemName: String
    var hoverColor: Color = Theme.textPrimary
    var hoverFill: Color = .white
    var action: () -> Void = {}
    @State private var hovering = false
    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(hovering ? hoverColor : Theme.textSecondary)
                .frame(width: 28, height: 28)
                .background(Circle().fill(hoverFill.opacity(hovering ? 0.12 : 0)))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.1), value: hovering)
    }
}

/// Small accent chip toggle ("Auto", "Center", link/lock). One vocabulary for
/// every inline panel action; replaces the per-panel hand-rolled variants.
struct ChipToggle: View {
    var label: String? = nil
    var systemName: String? = nil
    let isOn: Bool
    /// Momentary chips are accent-styled actions (e.g. "Auto"), not states — they keep
    /// the accent look from `isOn` but never report a selected trait.
    var isMomentary: Bool = false
    /// Ghost action: outlined accent by default, fills accent on hover/press. Reads
    /// as an actionable accent button, not a stuck-on toggle.
    var ghostAccent: Bool = false
    var help: String = ""
    var action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                if let systemName {
                    Image(systemName: systemName).font(.system(size: 10, weight: .semibold))
                }
                if let label {
                    Text(label).font(.system(size: 10.5, weight: .semibold))
                }
            }
        }
        .buttonStyle(ChipButtonStyle(isOn: isOn, ghostAccent: ghostAccent, hovering: hovering))
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.12), value: hovering)
        .help(help)
        .accessibilityLabel(help.isEmpty ? (label ?? "") : help)
        .accessibilityAddTraits(isOn && !isMomentary ? [.isSelected] : [])
    }
}

private struct ChipButtonStyle: ButtonStyle {
    let isOn: Bool
    let ghostAccent: Bool
    let hovering: Bool

    func makeBody(configuration: Configuration) -> some View {
        let active = ghostAccent && (hovering || configuration.isPressed)
        let accentFill = isOn || active
        configuration.label
            .foregroundStyle(
                accentFill ? Theme.accentInk
                    : ghostAccent ? Theme.accentText
                    : (hovering ? Theme.textPrimary : Theme.textTertiary)
            )
            .padding(.horizontal, 9)
            .frame(height: 22)
            .background(
                Capsule().fill(
                    accentFill
                        ? AnyShapeStyle(LinearGradient(
                            colors: [Theme.accent, Theme.accentText],
                            startPoint: .top, endPoint: .bottom))
                        : ghostAccent
                            ? AnyShapeStyle(Color.clear)
                            : AnyShapeStyle(Color.white.opacity(hovering ? 0.10 : 0.04))
                )
            )
            .overlay(
                Capsule().stroke(
                    accentFill ? Color.white.opacity(0.25)
                        : ghostAccent ? Theme.accentText.opacity(0.45)
                        : Theme.hairlineStrong,
                    lineWidth: 1
                )
            )
            .contentShape(Capsule())
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

/// Primary action (Save): a vermilion soft rectangle — gradient fill, specular
/// top edge, soft glow. The squarer geometry keeps it distinct from the dock's
/// capsule; the only saturated button in the chrome.
struct AccentButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        AccentBody(configuration: configuration)
    }

    private struct AccentBody: View {
        let configuration: ButtonStyleConfiguration
        @State private var hovering = false
        private static let shape = RoundedRectangle(cornerRadius: 7, style: .continuous)

        var body: some View {
            configuration.label
                .font(Theme.label(12, .semibold))
                .foregroundStyle(Theme.accentInk)
                .padding(.horizontal, 16)
                .padding(.vertical, 7)
                .background(
                    Self.shape.fill(
                        LinearGradient(
                            colors: [Theme.accentText, Theme.accent],
                            startPoint: .top, endPoint: .bottom
                        )
                    )
                    .brightness(hovering ? 0.12 : 0)
                )
                .overlay(Self.shape.stroke(Color.white.opacity(hovering ? 0.55 : 0.3), lineWidth: 1))
                .scaleEffect(configuration.isPressed ? 0.97 : 1)
                .onHover { hovering = $0; pushCursor($0) }
                .animation(.easeOut(duration: 0.12), value: hovering)
                .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
        }

        private func pushCursor(_ inside: Bool) {
            if inside { NSCursor.pointingHand.push() } else { NSCursor.pop() }
        }
    }
}

/// Secondary action that floats bare on the stage: a subtle hairline outline
/// marks it as pressable at rest, with a faint fill fading in on hover.
struct BareButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        BareBody(configuration: configuration)
    }

    private struct BareBody: View {
        let configuration: ButtonStyleConfiguration
        @State private var hovering = false
        var body: some View {
            configuration.label
                .font(Theme.label(12, .medium))
                .foregroundStyle(Theme.textPrimary)
                .padding(.horizontal, 16)
                .padding(.vertical, 7)
                .background(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(Color.white.opacity(hovering ? 0.09 : 0))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .stroke(Color.white.opacity(hovering ? 0.28 : 0.16), lineWidth: 1)
                )
                .scaleEffect(configuration.isPressed ? 0.98 : 1)
                .onHover { hovering = $0; if $0 { NSCursor.pointingHand.push() } else { NSCursor.pop() } }
                .animation(.easeOut(duration: 0.12), value: hovering)
                .animation(.easeOut(duration: 0.1), value: configuration.isPressed)
        }
    }
}

/// Secondary action (Copy): a clear glass pill — faint fill, bright hairline.
struct GhostButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        GhostBody(configuration: configuration)
    }

    private struct GhostBody: View {
        let configuration: ButtonStyleConfiguration
        @State private var hovering = false
        var body: some View {
            configuration.label
                .font(Theme.label(12, .medium))
                .foregroundStyle(Theme.textPrimary)
                .padding(.horizontal, 16)
                .padding(.vertical, 7)
                .background(
                    Capsule().fill(Color.white.opacity(hovering ? 0.14 : 0.07))
                )
                .overlay(Capsule().stroke(Color.white.opacity(0.22), lineWidth: 1))
                .scaleEffect(configuration.isPressed ? 0.98 : 1)
                .onHover { hovering = $0 }
                .animation(.easeOut(duration: 0.12), value: hovering)
                .animation(.easeOut(duration: 0.1), value: configuration.isPressed)
        }
    }
}
