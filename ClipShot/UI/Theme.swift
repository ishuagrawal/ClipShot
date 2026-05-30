import SwiftUI

// MARK: - Design tokens

/// "Warm Graphite" design system (modern-minimal pro-tool school): a warm charcoal
/// chrome — sidebar, top tool bar, controls — cut from one calm material, with depth
/// from light hairlines and soft shadows rather than heavy neumorphism. A single cool
/// teal accent (complementary to the warm base) marks selection and active state, so it
/// pops against the warm chrome and recedes behind the colourful canvas. Type is SF Pro
/// with a disciplined hierarchy; numeric controls use SF Mono.
enum Theme {

    // Warm charcoal chrome. The sidebar + top bar share `surface`.
    static let surface       = Color(red: 0.086, green: 0.075, blue: 0.063)   // ~#16130F
    // The "lit" top face of raised controls (gradient pairs with `raisedBottom`).
    static let raisedTop     = Color(red: 0.137, green: 0.121, blue: 0.102)   // ~#231F1A
    static let raisedBottom  = Color(red: 0.105, green: 0.092, blue: 0.078)   // ~#1B1813
    // Recessed well fill — a hair darker than the surface.
    static let well          = Color(red: 0.063, green: 0.055, blue: 0.047)   // ~#100E0C
    // Canvas backdrop behind the preview — deepest, near-black warm.
    static let canvasBack    = Color(red: 0.043, green: 0.037, blue: 0.031)   // ~#0B0907

    // Light & shadow (the source of depth)
    static let topHighlight  = Color.white.opacity(0.055)
    static let hairline      = Color.white.opacity(0.07)
    static let hairlineStrong = Color.white.opacity(0.10)
    static let innerShadow   = Color.black.opacity(0.50)
    static let innerLip      = Color.white.opacity(0.04)
    static let dropShadow    = Color.black.opacity(0.40)
    static let edgeShadow    = Color.black.opacity(0.45)

    // Ink — warm whites/greys
    static let textPrimary   = Color(red: 0.953, green: 0.933, blue: 0.902)   // warm white
    static let textSecondary = Color(red: 0.655, green: 0.616, blue: 0.565)   // warm grey
    static let textTertiary  = Color(red: 0.420, green: 0.392, blue: 0.353)   // dim warm grey

    // Accent — cool teal (complementary to the warm base)
    static let accent        = Color(red: 0.157, green: 0.792, blue: 0.722)   // ~#28CAB8
    static let accentText    = Color(red: 0.247, green: 0.882, blue: 0.812)   // brighter teal for text on dark
    static let accentDim     = Color(red: 0.157, green: 0.792, blue: 0.722).opacity(0.15)
    static let accentGlow    = Color(red: 0.157, green: 0.792, blue: 0.722).opacity(0.45)

    // Geometry
    static let radius: CGFloat = 9
    static let radiusSmall: CGFloat = 7
    static let radiusPill: CGFloat = 8

    // Type — SF Pro hierarchy
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

/// The prominent teal action button (Save).
struct AccentButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Theme.label(12, .semibold))
            .foregroundStyle(Color(red: 0.043, green: 0.090, blue: 0.082))   // deep teal-ink
            .padding(.horizontal, 14)
            .padding(.vertical, 7)
            .background(
                RoundedRectangle(cornerRadius: Theme.radiusSmall, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [Theme.accentText, Theme.accent],
                            startPoint: .top, endPoint: .bottom
                        )
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: Theme.radiusSmall, style: .continuous)
                    .stroke(Color.white.opacity(0.25), lineWidth: 1)
                    .mask(LinearGradient(colors: [.white, .clear], startPoint: .top, endPoint: .bottom))
            )
            .shadow(color: Theme.accentGlow, radius: configuration.isPressed ? 2 : 7, y: 1)
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

/// The secondary (Copy) button — a quiet raised graphite key.
struct GhostButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Theme.label(12, .medium))
            .foregroundStyle(Theme.textPrimary)
            .padding(.horizontal, 14)
            .padding(.vertical, 7)
            .raised(cornerRadius: Theme.radiusSmall, pressed: configuration.isPressed)
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.easeOut(duration: 0.1), value: configuration.isPressed)
    }
}
