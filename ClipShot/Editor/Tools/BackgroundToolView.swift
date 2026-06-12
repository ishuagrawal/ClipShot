import AppKit
import SwiftUI

/// Background detail panel with style tiles and per-style controls.
struct BackgroundToolView: View {
    @ObservedObject var state: EditorState

    @State private var solid = Color.white
    @State private var gradientStart = Color(cgColor: BackgroundStyle.defaultGradientStart)
    @State private var gradientEnd = Color(cgColor: BackgroundStyle.defaultGradientEnd)
    @State private var gradientAngle = Double(BackgroundStyle.defaultGradientAngle)
    @State private var blur = 0.0
    @State private var noise = 0.0
    @State private var isSyncingControls = false
    @State private var isSyncingEffects = false

    private var style: BackgroundStyle { state.document.background }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            tiles
            config
            effects
        }
        .onAppear {
            syncControls(from: style)
            syncEffects(state.document.backgroundEffects)
        }
        .onChange(of: style) { _, newStyle in
            syncControls(from: newStyle)
        }
        .onChange(of: state.document.backgroundEffects) { _, fx in
            syncEffects(fx)
        }
    }

    /// Stackable post-effects (blur + grain) on top of any non-empty background.
    @ViewBuilder
    private var effects: some View {
        if style.kind != .none {
            Rectangle().fill(Theme.hairline).frame(height: 1).padding(.vertical, 2)
            HStack(spacing: 10) {
                InspectorRowLabel(text: "Blur")
                GlassSlider(
                    value: Binding(get: { blur }, set: { blur = $0; commitEffects() }),
                    range: 0...Double(BackgroundEffects.maximumBlurRadius),
                    accessibilityLabel: "Background blur",
                    accessibilityValue: { "\(Int($0.rounded()))" }
                )
                InspectorValueLabel(text: "\(Int(blur))")
            }
            HStack(spacing: 10) {
                InspectorRowLabel(text: "Noise")
                GlassSlider(
                    value: Binding(get: { noise }, set: { noise = $0; commitEffects() }),
                    range: 0...Double(BackgroundEffects.maximumNoiseOpacity * 100),
                    accessibilityLabel: "Background noise",
                    accessibilityValue: { "\(Int($0.rounded())) percent" }
                )
                InspectorValueLabel(text: "\(Int(noise))%")
            }
        }
    }

    /// Style lenses: each background style is a round glass bead. The active one
    /// wears a vermilion ring and lifts slightly — same vocabulary as the color wells.
    private var tiles: some View {
        HStack(spacing: 12) {
            ForEach(BackgroundStyle.Kind.allCases, id: \.self) { kind in
                let selected = style.kind == kind
                Button {
                    select(kind)
                } label: {
                    tileSwatch(kind)
                        .frame(width: 36, height: 36)
                        .clipShape(Circle())
                        .overlay(
                            // Specular highlight: every lens reads as glass.
                            Circle().fill(
                                RadialGradient(
                                    colors: [.white.opacity(0.4), .clear],
                                    center: .init(x: 0.32, y: 0.22),
                                    startRadius: 0, endRadius: 16
                                )
                            )
                        )
                        .overlay(
                            Circle().stroke(
                                selected ? Theme.accent : Color.white.opacity(0.18),
                                lineWidth: selected ? 2 : 1
                            )
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
            Spacer(minLength: 0)
        }
    }

    @ViewBuilder
    private func tileSwatch(_ kind: BackgroundStyle.Kind) -> some View {
        switch kind {
        case .none:
            Circle()
                .fill(Color.black.opacity(0.3))
                .overlay(
                    Image(systemName: "circle.slash")
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.textTertiary)
                )
        case .solid:
            Circle().fill(solid)
        case .gradient:
            Circle().fill(
                LinearGradient(
                    colors: [gradientStart, gradientEnd],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
        case .dynamic:
            Circle().fill(
                AngularGradient(
                    colors: [
                        Color(red: 0.95, green: 0.35, blue: 0.45),
                        Color(red: 0.45, green: 0.45, blue: 0.95),
                        Color(red: 0.35, green: 0.85, blue: 0.75),
                        Color(red: 0.95, green: 0.35, blue: 0.45)
                    ],
                    center: .center
                )
            )
            .overlay(
                Image(systemName: "sparkles")
                    .font(.system(size: 12))
                    .foregroundStyle(.white.opacity(0.9))
            )
        }
    }

    private func tileName(_ kind: BackgroundStyle.Kind) -> String {
        switch kind {
        case .none:
            return "None"
        case .solid:
            return "Solid"
        case .gradient:
            return "Gradient"
        case .dynamic:
            return "Dynamic"
        }
    }

    @ViewBuilder
    private var config: some View {
        switch style.kind {
        case .none:
            Text("No background")
                .font(Theme.label(12))
                .foregroundStyle(Theme.textTertiary)
        case .solid:
            HStack {
                InspectorRowLabel(text: "Color")
                GlassColorWell(selection: $solid, label: "Background color")
                    .onChange(of: solid) { _, _ in
                        guard !isSyncingControls else { return }
                        commit(.solidColor(NSColor(solid).cgColor))
                    }
            }
        case .gradient:
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 8) {
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
                            set: { newValue in
                                gradientAngle = newValue
                                applyGradient()
                            }
                        ),
                        range: 0...360,
                        accessibilityLabel: "Gradient angle",
                        accessibilityValue: { "\(Int($0.rounded())) degrees" }
                    )
                    InspectorValueLabel(text: "\(Int(gradientAngle))°")
                }
            }
        case .dynamic:
            Text("Auto-generated from image").font(Theme.label(12)).foregroundStyle(Theme.textTertiary)
        }
    }

    private func select(_ kind: BackgroundStyle.Kind) {
        switch kind {
        case .none:
            commit(.none)
        case .solid:
            commit(.solidColor(NSColor(solid).cgColor))
        case .gradient:
            applyGradient()
        case .dynamic:
            commit(.dynamic)
        }
    }

    private func applyGradient() {
        commit(
            .gradient(
                start: NSColor(gradientStart).cgColor,
                end: NSColor(gradientEnd).cgColor,
                angleDegrees: CGFloat(gradientAngle)
            )
        )
    }

    private func commit(_ next: BackgroundStyle) {
        guard next != style else { return }
        state.performCommand(SetBackgroundCommand(from: style, to: next))
    }

    private func syncControls(from style: BackgroundStyle) {
        isSyncingControls = true
        defer {
            // Re-enable writes after the onChange cascade settles, staying on the main actor.
            Task { @MainActor in
                isSyncingControls = false
            }
        }

        switch style {
        case .none:
            break
        case .solidColor(let color):
            solid = Color(cgColor: color)
        case .gradient(let start, let end, let angle):
            gradientStart = Color(cgColor: start)
            gradientEnd = Color(cgColor: end)
            gradientAngle = Double(angle)
        case .dynamic:
            break
        }
    }

    private func commitEffects() {
        guard !isSyncingEffects else { return }
        let from = state.document.backgroundEffects
        let to = BackgroundEffects(blurRadius: CGFloat(blur), noiseOpacity: CGFloat(noise / 100))
        guard to != from else { return }
        state.performCommand(SetBackgroundEffectsCommand(from: from, to: to))
    }

    private func syncEffects(_ fx: BackgroundEffects) {
        let nextBlur = Double(fx.blurRadius)
        let nextNoise = Double(fx.noiseOpacity * 100)
        guard blur != nextBlur || noise != nextNoise else { return }
        isSyncingEffects = true
        defer { Task { @MainActor in isSyncingEffects = false } }
        blur = nextBlur
        noise = nextNoise
    }
}
