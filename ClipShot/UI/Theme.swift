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
    static let stageDot       = Color.white.opacity(0.045)

    // MARK: Ink (warm white, contrast-checked on `surface`)
    static let textPrimary   = Color(red: 0.961, green: 0.945, blue: 0.918)   // #F5F1EA ~15:1
    static let textSecondary = Color(red: 0.690, green: 0.655, blue: 0.604)   // #B0A79A ~7:1
    static let textTertiary  = Color(red: 0.553, green: 0.518, blue: 0.471)   // #8D8478 ~4.6:1

    // MARK: Accent — vermilion, the registration-mark color
    static let accent        = Color(red: 1.0, green: 0.361, blue: 0.220)     // #FF5C38
    static let accentText    = Color(red: 1.0, green: 0.557, blue: 0.420)     // #FF8E6B on dark ~7:1
    static let accentDim     = Color(red: 1.0, green: 0.361, blue: 0.220).opacity(0.14)
    static let accentFocus   = Color(red: 1.0, green: 0.361, blue: 0.220).opacity(0.55)
    static let accentInk     = Color(red: 0.173, green: 0.055, blue: 0.020)   // ink on solid accent

    /// AppKit/CoreAnimation consumers (selection halo, drag handles).
    static let accentCG = CGColor(red: 1.0, green: 0.361, blue: 0.220, alpha: 1)
    static let stageCG  = CGColor(red: 0.075, green: 0.067, blue: 0.059, alpha: 1)

    // MARK: Geometry
    static let radiusControl: CGFloat = 7
    static let radiusPill: CGFloat = 11
    static let sidebarWidth: CGFloat = 276
    static let topBarHeight: CGFloat = 52
    static let statusBarHeight: CGFloat = 34

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

/// The brand glyph: two opposing crop/registration corners drawn in accent,
/// mirroring the stage's corner ticks. Used by the top bar wordmark and menu popover.
struct BrandTickGlyph: View {
    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width, h = geo.size.height
            Path { p in
                p.move(to: CGPoint(x: 0, y: h * 0.62))
                p.addLine(to: CGPoint(x: 0, y: 0))
                p.addLine(to: CGPoint(x: w * 0.62, y: 0))
                p.move(to: CGPoint(x: w, y: h * 0.38))
                p.addLine(to: CGPoint(x: w, y: h))
                p.addLine(to: CGPoint(x: w * 0.38, y: h))
            }
            .stroke(Theme.accent, style: StrokeStyle(lineWidth: 2, lineCap: .round))
        }
        .accessibilityHidden(true)
    }
}

// MARK: - Shared text roles

/// Sentence-case section label used to head each inspector group.
struct SectionLabel: View {
    let text: String
    var body: some View {
        Text(text)
            .font(Theme.section())
            .foregroundStyle(Theme.textSecondary)
    }
}

/// Inspector row label (left column) — shared by every tool panel.
struct InspectorRowLabel: View {
    let text: String
    var body: some View {
        Text(text)
            .font(Theme.label())
            .foregroundStyle(Theme.textSecondary)
            .frame(width: 56, alignment: .leading)
    }
}

/// Inspector numeric readout (right column) — always monospaced, always aligned.
struct InspectorValueLabel: View {
    let text: String
    var body: some View {
        Text(text)
            .font(Theme.mono(11.5, .semibold))
            .foregroundStyle(Theme.textPrimary)
            .frame(width: 40, alignment: .trailing)
    }
}

/// Monospaced HUD readout for the status bar (dimensions, zoom).
struct HUDReadout: View {
    let label: String
    let value: String
    var body: some View {
        HStack(spacing: 6) {
            Text(label)
                .font(Theme.section(10.5))
                .foregroundStyle(Theme.textTertiary)
            Text(value)
                .font(Theme.mono(11.5, .semibold))
                .foregroundStyle(Theme.textSecondary)
        }
        .accessibilityElement(children: .combine)
    }
}

/// Keycap glyph for shortcut hints ("⌃", "⇧", "5").
struct Keycap: View {
    let text: String
    var body: some View {
        Text(text)
            .font(Theme.mono(11, .semibold))
            .foregroundStyle(Theme.textSecondary)
            .frame(minWidth: 22)
            .frame(height: 22)
            .padding(.horizontal, 3)
            .background(
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(Theme.inputFill)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .stroke(Theme.hairlineStrong, lineWidth: 1)
            )
    }
}

// MARK: - Containers

/// Flat inset field surface: filled, hairline border, no carved well.
struct InsetField: ViewModifier {
    var cornerRadius: CGFloat = Theme.radiusControl
    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(Theme.inputFill)
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(Theme.hairline, lineWidth: 1)
            )
    }
}

/// Floating container: surface fill + hairline + one soft drop shadow (it floats).
struct FloatingBar: ViewModifier {
    var cornerRadius: CGFloat = Theme.radiusPill
    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(Theme.surface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(Theme.hairline, lineWidth: 1)
            )
            .shadow(color: Theme.floatShadow, radius: 16, y: 6)
    }
}

extension View {
    func insetField(cornerRadius: CGFloat = Theme.radiusControl) -> some View {
        modifier(InsetField(cornerRadius: cornerRadius))
    }
    func floatingBar(cornerRadius: CGFloat = Theme.radiusPill) -> some View {
        modifier(FloatingBar(cornerRadius: cornerRadius))
    }
}

/// Collapsible inspector section: chevron + title header, optional trailing accessory,
/// hairline below. The inspector is a stack of these — no routing, no close buttons.
struct InspectorSection<Accessory: View, Content: View>: View {
    let title: String
    @ViewBuilder var accessory: () -> Accessory
    @ViewBuilder var content: () -> Content

    @State private var expanded = true
    @State private var hovering = false

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
        VStack(alignment: .leading, spacing: 0) {
            Button {
                expanded.toggle()
            } label: {
                HStack(spacing: 7) {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 8.5, weight: .bold))
                        .foregroundStyle(Theme.textTertiary)
                        .rotationEffect(.degrees(expanded ? 90 : 0))
                    Text(title)
                        .font(Theme.section(11.5))
                        .foregroundStyle(hovering ? Theme.textPrimary : Theme.textSecondary)
                    Spacer(minLength: 8)
                }
                .padding(.horizontal, 14)
                .frame(height: 38)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .onHover { hovering = $0 }
            .overlay(alignment: .trailing) {
                accessory()
                    .padding(.trailing, 14)
            }
            .accessibilityLabel(title)
            .accessibilityValue(expanded ? "Expanded" : "Collapsed")

            if expanded {
                content()
                    .padding(.horizontal, 16)
                    .padding(.bottom, 16)
            }

            Rectangle().fill(Theme.hairline).frame(height: 1)
        }
        .animation(.easeOut(duration: 0.16), value: expanded)
    }
}

/// Vertical tool-rail button: icon with a left-edge accent tick when active,
/// the rail's version of a pressed drafting tool.
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
                .foregroundStyle(isActive ? Theme.accentText : (hovering ? Theme.textPrimary : Theme.textSecondary))
                .frame(width: 36, height: 36)
                .background(
                    RoundedRectangle(cornerRadius: Theme.radiusControl, style: .continuous)
                        .fill(isActive ? Theme.accentDim : (hovering ? Theme.surfaceHover : .clear))
                )
                .overlay(alignment: .leading) {
                    if isActive {
                        Capsule()
                            .fill(Theme.accent)
                            .frame(width: 2, height: 18)
                            .offset(x: -7)
                    }
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.12), value: hovering)
        .help(shortcut.map { "\(label)  \($0)" } ?? label)
        .accessibilityLabel(label)
        .accessibilityAddTraits(isActive ? [.isSelected] : [])
    }
}

// MARK: - Controls

/// Flat slider: filled track, vermilion progress, plain knob.
struct FlatSlider: View {
    @Binding var value: Double
    var range: ClosedRange<Double>
    var accessibilityLabel: String
    var accessibilityValue: (Double) -> String = { "\(Int($0.rounded()))" }
    var onEditingChanged: (Bool) -> Void = { _ in }

    @State private var isEditing = false
    @State private var hovering = false

    private let trackHeight: CGFloat = 4
    private let knob: CGFloat = 13

    var body: some View {
        // GeometryReader is intentional: knob offset arithmetic needs the numeric track width.
        GeometryReader { geo in
            let width = geo.size.width
            let span = range.upperBound - range.lowerBound
            let fraction = span > 0 ? (value - range.lowerBound) / span : 0
            let clamped = min(max(fraction, 0), 1)
            let knobX = CGFloat(clamped) * (width - knob) + knob / 2

            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Theme.inputFill)
                    .frame(height: trackHeight)
                    .overlay(Capsule().stroke(Theme.hairline, lineWidth: 1))
                // Neutral at rest; ignites to accent while the user is on it, so a
                // panel full of sliders doesn't read as a wall of vermilion.
                Capsule()
                    .fill(isEditing || hovering ? Theme.accent : Color.white.opacity(0.28))
                    .frame(width: max(knobX, trackHeight), height: trackHeight)
                Circle()
                    .fill(Theme.textPrimary)
                    .frame(width: knob, height: knob)
                    .overlay(Circle().stroke(Theme.accentFocus, lineWidth: isEditing ? 3 : 0))
                    .offset(x: knobX - knob / 2)
                    .scaleEffect(isEditing ? 1.12 : (hovering ? 1.06 : 1))
            }
            .frame(height: knob)
            .allowsHitTesting(false)
            .overlay {
                Slider(value: $value, in: range, onEditingChanged: handleEditingChanged)
                    .opacity(0.001)
                    .accessibilityLabel(Text(accessibilityLabel))
                    .accessibilityValue(Text(accessibilityValue(value)))
            }
            .onHover { hovering = $0 }
            .animation(.easeOut(duration: 0.12), value: isEditing)
            .animation(.easeOut(duration: 0.12), value: hovering)
        }
        .frame(height: knob)
    }

    private func handleEditingChanged(_ editing: Bool) {
        isEditing = editing
        onEditingChanged(editing)
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
    var action: () -> Void = {}
    @State private var hovering = false
    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(hovering ? Theme.textPrimary : Theme.textSecondary)
                .frame(width: 28, height: 28)
                .background(
                    RoundedRectangle(cornerRadius: Theme.radiusControl, style: .continuous)
                        .fill(hovering ? Theme.surfaceHover : .clear)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.1), value: hovering)
    }
}

/// Small accent chip toggle ("Auto", "Concentric", link/lock). One vocabulary for
/// every inline panel action; replaces the per-panel hand-rolled variants.
struct ChipToggle: View {
    var label: String? = nil
    var systemName: String? = nil
    let isOn: Bool
    /// Momentary chips are accent-styled actions (e.g. "Auto"), not states — they keep
    /// the accent look from `isOn` but never report a selected trait.
    var isMomentary: Bool = false
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
            .foregroundStyle(isOn ? Theme.accentText : (hovering ? Theme.textSecondary : Theme.textTertiary))
            .padding(.horizontal, 8)
            .frame(height: 22)
            .background(
                Capsule().fill(isOn ? Theme.accentDim : (hovering ? Theme.surfaceHover : .clear))
            )
            .overlay(
                Capsule().stroke(isOn ? Theme.accentFocus.opacity(0.4) : Theme.hairline, lineWidth: 1)
            )
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.12), value: hovering)
        .help(help)
        .accessibilityLabel(help.isEmpty ? (label ?? "") : help)
        .accessibilityAddTraits(isOn && !isMomentary ? [.isSelected] : [])
    }
}

/// Primary action (Save): flat solid vermilion, dark ink, no gradient or glow.
struct AccentButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Theme.label(12, .semibold))
            .foregroundStyle(Theme.accentInk)
            .padding(.horizontal, 14)
            .padding(.vertical, 7)
            .background(
                RoundedRectangle(cornerRadius: Theme.radiusControl, style: .continuous)
                    .fill(configuration.isPressed ? Theme.accent.opacity(0.85) : Theme.accent)
            )
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

/// Secondary action (Copy): flat surface + hairline ghost.
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
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
                .background(
                    RoundedRectangle(cornerRadius: Theme.radiusControl, style: .continuous)
                        .fill(hovering ? Theme.surfaceHover : Theme.surface)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.radiusControl, style: .continuous)
                        .stroke(Theme.hairlineStrong, lineWidth: 1)
                )
                .scaleEffect(configuration.isPressed ? 0.98 : 1)
                .onHover { hovering = $0 }
                .animation(.easeOut(duration: 0.12), value: hovering)
                .animation(.easeOut(duration: 0.1), value: configuration.isPressed)
        }
    }
}
