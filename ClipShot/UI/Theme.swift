import SwiftUI

// MARK: - Design tokens

enum Theme {

    // MARK: Dark Canvas surfaces (cool neutral)
    static let canvas        = Color(red: 0.067, green: 0.075, blue: 0.086)   // #111316 stage
    static let surface       = Color(red: 0.102, green: 0.114, blue: 0.129)   // #1A1D21 floating panels/bars
    static let surfaceHover  = Color(red: 0.133, green: 0.149, blue: 0.169)   // #22262B hover tint
    static let surfaceActive = Color(red: 0.157, green: 0.792, blue: 0.722).opacity(0.16)
    static let inputFill     = Color(red: 0.125, green: 0.137, blue: 0.153)   // #202327 inset fields

    // MARK: Lines & shadow
    static let hairline       = Color.white.opacity(0.08)
    static let hairlineStrong = Color.white.opacity(0.14)
    static let floatShadow    = Color.black.opacity(0.45)

    // MARK: Ink (contrast-checked on `surface`)
    static let textPrimary   = Color(red: 0.949, green: 0.957, blue: 0.965)   // #F2F4F6 ~16:1
    static let textSecondary = Color(red: 0.635, green: 0.663, blue: 0.698)   // #A2A9B2 ~7:1
    static let textTertiary  = Color(red: 0.522, green: 0.545, blue: 0.576)   // #858B93 ~4.9:1
    static let textDisabled  = Color(red: 0.353, green: 0.376, blue: 0.408)   // #5A6068 decorative only

    // MARK: Accent — teal (restrained)
    static let accent        = Color(red: 0.157, green: 0.792, blue: 0.722)   // #28CAB8
    static let accentText    = Color(red: 0.247, green: 0.878, blue: 0.804)   // #3FE0CD on dark
    static let accentDim     = Color(red: 0.157, green: 0.792, blue: 0.722).opacity(0.16)
    static let accentFocus   = Color(red: 0.157, green: 0.792, blue: 0.722).opacity(0.55)

    // MARK: Geometry
    static let radiusPanel: CGFloat = 12
    static let radiusControl: CGFloat = 8
    static let radiusPill: CGFloat = 12

    // MARK: Transition-only aliases (removed in a later cleanup phase; kept so Warm Graphite
    // components still compile during migration).
    static let canvasBack    = Color(red: 0.067, green: 0.075, blue: 0.086)
    static let raisedTop     = Color(red: 0.137, green: 0.149, blue: 0.169)
    static let raisedBottom  = Color(red: 0.102, green: 0.114, blue: 0.129)
    static let well          = Color(red: 0.078, green: 0.086, blue: 0.098)
    static let topHighlight  = Color.white.opacity(0.05)
    static let innerShadow   = Color.black.opacity(0.45)
    static let innerLip      = Color.white.opacity(0.04)
    static let dropShadow    = Color.black.opacity(0.40)
    static let edgeShadow    = Color.black.opacity(0.45)
    static let accentGlow    = Color(red: 0.157, green: 0.792, blue: 0.722).opacity(0.45)
    static let radius: CGFloat = 12
    static let radiusSmall: CGFloat = 8

    // MARK: Type — SF Pro hierarchy, fixed scale ~1.2 ratio
    static func title(_ size: CGFloat = 15, _ weight: Font.Weight = .semibold) -> Font {
        .system(size: size, weight: weight, design: .default)
    }
    static func section(_ size: CGFloat = 12, _ weight: Font.Weight = .medium) -> Font {
        .system(size: size, weight: weight, design: .default)
    }
    static func label(_ size: CGFloat = 12, _ weight: Font.Weight = .medium) -> Font {
        .system(size: size, weight: weight, design: .default)
    }
    static func mono(_ size: CGFloat = 12, _ weight: Font.Weight = .medium) -> Font {
        .system(size: size, weight: weight, design: .monospaced)
    }
}

// MARK: - Elevation primitives

/// Recessed: the element looks carved *into* the surface — a darker well with a soft
/// inner shadow on the top edge and a warm hairline rim. Used for inputs and tracks.
struct Recessed: ViewModifier {
    var cornerRadius: CGFloat = Theme.radiusSmall
    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(
                        Theme.well
                            .shadow(.inner(color: Theme.innerShadow, radius: 2.5, x: 0, y: 1.5))
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(Color.black.opacity(0.30), lineWidth: 1)
            )
    }
}

/// Raised: the element sits *above* the surface like a soft key — a top-lit gradient,
/// a 1px specular highlight on the top edge, a warm hairline rim, and a soft shadow.
struct Raised: ViewModifier {
    var cornerRadius: CGFloat = Theme.radius
    var pressed: Bool = false
    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: pressed
                                ? [Theme.raisedBottom, Theme.raisedBottom]
                                : [Theme.raisedTop, Theme.raisedBottom],
                            startPoint: .top, endPoint: .bottom
                        )
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(Theme.topHighlight, lineWidth: 1)
                    .mask(LinearGradient(colors: [.white, .clear], startPoint: .top, endPoint: .bottom))
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(Color.black.opacity(0.30), lineWidth: 1)
                    .mask(LinearGradient(colors: [.clear, .black], startPoint: .top, endPoint: .bottom))
            )
            .shadow(color: pressed ? .clear : Theme.dropShadow, radius: pressed ? 0 : 3, y: pressed ? 0 : 1.5)
    }
}

extension View {
    func recessed(cornerRadius: CGFloat = Theme.radiusSmall) -> some View {
        modifier(Recessed(cornerRadius: cornerRadius))
    }
    func raised(cornerRadius: CGFloat = Theme.radius, pressed: Bool = false) -> some View {
        modifier(Raised(cornerRadius: cornerRadius, pressed: pressed))
    }
}

// MARK: - Dark Canvas components

/// Sentence-case section label (replaces the tracked-caps PanelTitle).
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

/// Inspector numeric readout (right column) — shared by every tool panel.
struct InspectorValueLabel: View {
    let text: String
    var body: some View {
        Text(text)
            .font(Theme.mono(12, .semibold))
            .foregroundStyle(Theme.textPrimary)
            .frame(width: 36, alignment: .trailing)
    }
}

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
            .shadow(color: Theme.floatShadow, radius: 18, y: 8)
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

/// Flat slider: filled track, teal progress, plain teal knob. No recessed/raised pomp.
struct FlatSlider: View {
    @Binding var value: Double
    var range: ClosedRange<Double>
    var accessibilityLabel: String
    var accessibilityValue: (Double) -> String = { "\(Int($0.rounded()))" }
    var onEditingChanged: (Bool) -> Void = { _ in }

    @State private var isEditing = false
    @State private var hovering = false

    private let trackHeight: CGFloat = 4
    private let knob: CGFloat = 14

    var body: some View {
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
                Capsule()
                    .fill(Theme.accent)
                    .frame(width: max(knobX, trackHeight), height: trackHeight)
                Circle()
                    .fill(Theme.accent)
                    .frame(width: knob, height: knob)
                    .overlay(Circle().stroke(Theme.hairlineStrong, lineWidth: 1))
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
                .font(.system(size: 15, weight: .medium))
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

/// Compact icon button for the bottom action bar (undo/redo). Flat, hover tint only.
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

// MARK: - Section label

/// Tracked caps section title used inside detail-panel groups.
struct PanelTitle: View {
    let text: String
    var body: some View {
        Text(text.uppercased())
            .font(Theme.label(10.5, .semibold))
            .tracking(1.4)
            .foregroundStyle(Theme.textTertiary)
    }
}

// MARK: - Graphite slider

/// Custom slider: a recessed track, a teal fill, and a raised knob.
/// Mirrors SwiftUI.Slider's API surface used in this app (value, range, onEditingChanged).
struct GraphiteSlider: View {
    @Binding var value: Double
    var range: ClosedRange<Double>
    var accessibilityLabel: String
    var accessibilityValue: (Double) -> String = { "\(Int($0.rounded()))" }
    var onEditingChanged: (Bool) -> Void = { _ in }

    @State private var isEditing = false

    private let trackHeight: CGFloat = 5
    private let knob: CGFloat = 15

    var body: some View {
        GeometryReader { geo in
            let width = geo.size.width
            let fraction = range.upperBound > range.lowerBound
                ? (value - range.lowerBound) / (range.upperBound - range.lowerBound)
                : 0
            let clamped = min(max(fraction, 0), 1)
            let knobX = CGFloat(clamped) * (width - knob) + knob / 2

            ZStack(alignment: .leading) {
                // Recessed track
                Capsule()
                    .fill(Color.clear)
                    .frame(height: trackHeight)
                    .recessed(cornerRadius: trackHeight / 2)

                // Teal fill
                Capsule()
                    .fill(
                        LinearGradient(
                            colors: [Theme.accent.opacity(0.9), Theme.accent],
                            startPoint: .leading, endPoint: .trailing
                        )
                    )
                    .frame(width: max(knobX, trackHeight), height: trackHeight)
                    .shadow(color: Theme.accentGlow.opacity(0.5), radius: 3)

                // Raised knob
                Circle()
                    .fill(Color.clear)
                    .frame(width: knob, height: knob)
                    .raised(cornerRadius: knob / 2)
                    .overlay(
                        Circle().stroke(Theme.accent.opacity(isEditing ? 0.95 : 0), lineWidth: 2)
                    )
                    .shadow(color: isEditing ? Theme.accentGlow : .clear, radius: 5)
                    .offset(x: knobX - knob / 2)
                    .scaleEffect(isEditing ? 1.12 : 1)
            }
            .frame(height: knob)
            .allowsHitTesting(false)
            .overlay {
                Slider(
                    value: $value,
                    in: range,
                    onEditingChanged: handleEditingChanged
                )
                .opacity(0.001)
                .accessibilityLabel(Text(accessibilityLabel))
                .accessibilityValue(Text(accessibilityValue(value)))
            }
            .animation(.spring(response: 0.25, dampingFraction: 0.7), value: isEditing)
        }
        .frame(height: knob)
    }

    private func handleEditingChanged(_ editing: Bool) {
        isEditing = editing
        onEditingChanged(editing)
    }
}

// MARK: - Buttons

/// A compact icon button used in the bottom bar (undo/redo/zoom). Raised on hover/press.
struct BarIconButton: View {
    let systemName: String
    var action: () -> Void = {}
    @State private var hovering = false
    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(hovering ? Theme.textPrimary : Theme.textSecondary)
                .frame(width: 28, height: 28)
                .contentShape(Rectangle())
        }
        .buttonStyle(KeyButtonStyle())
        .onHover { hovering = $0 }
    }
}

/// A pressable "key": flat on the surface at rest, raises on hover, depresses on press.
struct KeyButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        KeyButtonBody(configuration: configuration)
    }

    private struct KeyButtonBody: View {
        let configuration: ButtonStyleConfiguration
        @State private var hovering = false
        var body: some View {
            let raised = hovering || configuration.isPressed
            configuration.label
                .background {
                    if raised {
                        RoundedRectangle(cornerRadius: Theme.radiusSmall, style: .continuous)
                            .fill(Color.clear)
                            .raised(cornerRadius: Theme.radiusSmall, pressed: configuration.isPressed)
                    }
                }
                .onHover { hovering = $0 }
                .animation(.easeOut(duration: 0.12), value: hovering)
                .animation(.easeOut(duration: 0.08), value: configuration.isPressed)
        }
    }
}

/// Primary action (Save): flat solid teal, no gradient/specular/glow.
struct AccentButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Theme.label(12, .semibold))
            .foregroundStyle(Color(red: 0.031, green: 0.137, blue: 0.122))   // deep teal ink
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
                        .stroke(Theme.hairline, lineWidth: 1)
                )
                .scaleEffect(configuration.isPressed ? 0.98 : 1)
                .onHover { hovering = $0 }
                .animation(.easeOut(duration: 0.12), value: hovering)
                .animation(.easeOut(duration: 0.1), value: configuration.isPressed)
        }
    }
}
