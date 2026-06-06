import AppKit
import SwiftUI

/// Background detail panel with style tiles and per-style controls.
struct BackgroundToolView: View {
    @ObservedObject var state: EditorState

    @State private var solid = Color.white
    @State private var gradientStart = Color(cgColor: BackgroundStyle.defaultGradientStart)
    @State private var gradientEnd = Color(cgColor: BackgroundStyle.defaultGradientEnd)
    @State private var gradientAngle = Double(BackgroundStyle.defaultGradientAngle)
    @State private var isSyncingControls = false

    private var style: BackgroundStyle { state.document.background }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Background")
                .font(Theme.title(13))
                .foregroundStyle(Theme.textPrimary)
            tiles
            config
        }
        .padding(16)
        .onAppear { syncControls(from: style) }
        .onChange(of: style) { _, newStyle in
            syncControls(from: newStyle)
        }
    }

    private var tiles: some View {
        HStack(spacing: 9) {
            ForEach(BackgroundStyle.Kind.allCases, id: \.self) { kind in
                let selected = style.kind == kind
                Button {
                    select(kind)
                } label: {
                    tileSwatch(kind)
                        .frame(width: 42, height: 42)
                        .clipShape(RoundedRectangle(cornerRadius: Theme.radiusControl, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: Theme.radiusControl, style: .continuous)
                                .stroke(selected ? Theme.accent : Theme.hairline, lineWidth: selected ? 2 : 1)
                        )
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(tileName(kind))
            }
        }
    }

    @ViewBuilder
    private func tileSwatch(_ kind: BackgroundStyle.Kind) -> some View {
        let shape = RoundedRectangle(cornerRadius: Theme.radiusControl, style: .continuous)
        switch kind {
        case .none:
            shape
                .fill(Theme.inputFill)
                .overlay(
                    Image(systemName: "circle.slash")
                        .font(.system(size: 14))
                        .foregroundStyle(Theme.textTertiary)
                )
        case .solid:
            shape.fill(solid)
        case .gradient:
            shape.fill(
                LinearGradient(
                    colors: [gradientStart, gradientEnd],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
        case .dynamic:
            shape.fill(
                LinearGradient(
                    colors: [
                        Color(red: 0.95, green: 0.35, blue: 0.45),
                        Color(red: 0.45, green: 0.45, blue: 0.95),
                        Color(red: 0.35, green: 0.85, blue: 0.75)
                    ],
                    startPoint: .topLeading, endPoint: .bottomTrailing
                )
            )
            .overlay(
                Image(systemName: "sparkles")
                    .font(.system(size: 13))
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
                ColorPicker("", selection: $solid, supportsOpacity: false)
                    .labelsHidden()
                    .onChange(of: solid) { _, _ in
                        guard !isSyncingControls else { return }
                        commit(.solidColor(NSColor(solid).cgColor))
                    }
            }
        case .gradient:
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    InspectorRowLabel(text: "Colors")
                    ColorPicker("", selection: $gradientStart, supportsOpacity: false)
                        .labelsHidden()
                        .onChange(of: gradientStart) { _, _ in
                            guard !isSyncingControls else { return }
                            applyGradient()
                        }
                    ColorPicker("", selection: $gradientEnd, supportsOpacity: false)
                        .labelsHidden()
                        .onChange(of: gradientEnd) { _, _ in
                            guard !isSyncingControls else { return }
                            applyGradient()
                        }
                }
                HStack(spacing: 10) {
                    InspectorRowLabel(text: "Angle")
                    FlatSlider(
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
}
