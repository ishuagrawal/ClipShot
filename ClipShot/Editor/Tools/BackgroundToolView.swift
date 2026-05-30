import AppKit
import SwiftUI

/// Background detail panel with style tiles and per-style controls.
struct BackgroundToolView: View {
    @ObservedObject var state: EditorState

    @State private var solid = Color.white
    @State private var gradientStart = Color(red: 0.12, green: 0.36, blue: 0.72)
    @State private var gradientEnd = Color(red: 0.20, green: 0.65, blue: 0.85)
    @State private var gradientAngle = 135.0
    @State private var blurRadius = 24.0
    @State private var isSyncingControls = false

    private var style: BackgroundStyle { state.document.background }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 9) {
                PanelTitle(text: "Style")
                tiles
            }
            Rectangle().fill(Theme.hairline).frame(height: 1)
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
                        .clipShape(RoundedRectangle(cornerRadius: Theme.radius, style: .continuous))
                        // Top specular highlight → reads as a raised cap.
                        .overlay(
                            RoundedRectangle(cornerRadius: Theme.radius, style: .continuous)
                                .stroke(Theme.topHighlight, lineWidth: 1)
                                .mask(LinearGradient(colors: [.white, .clear], startPoint: .top, endPoint: .center))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: Theme.radius, style: .continuous)
                                .stroke(
                                    selected ? Theme.accent : Color.black.opacity(0.45),
                                    lineWidth: selected ? 2 : 1
                                )
                        )
                        .shadow(color: selected ? Theme.accentGlow : .black.opacity(0.4),
                                radius: selected ? 7 : 3, y: selected ? 0 : 2)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(tileName(kind))
            }
        }
    }

    @ViewBuilder
    private func tileSwatch(_ kind: BackgroundStyle.Kind) -> some View {
        let shape = RoundedRectangle(cornerRadius: Theme.radius, style: .continuous)
        switch kind {
        case .none:
            shape
                .fill(
                    LinearGradient(
                        colors: [Theme.raisedTop, Theme.raisedBottom],
                        startPoint: .top, endPoint: .bottom
                    )
                )
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
        case .blurExtend:
            shape
                .fill(
                    LinearGradient(
                        colors: [Color(white: 0.4), Color(white: 0.22)],
                        startPoint: .top, endPoint: .bottom
                    )
                )
                .overlay(
                    Image(systemName: "drop.halffull")
                        .font(.system(size: 14))
                        .foregroundStyle(.white.opacity(0.75))
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
        case .blurExtend:
            return "Blur extend"
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
                rowLabel("Color")
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
                    rowLabel("Colors")
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
                    rowLabel("Angle")
                    GraphiteSlider(
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
                    valueLabel("\(Int(gradientAngle))°")
                }
            }
        case .blurExtend:
            HStack(spacing: 10) {
                rowLabel("Radius")
                GraphiteSlider(
                    value: Binding(
                        get: { blurRadius },
                        set: { newValue in
                            blurRadius = newValue
                            commit(.blurExtend(radius: CGFloat(newValue)))
                        }
                    ),
                    range: 0...80,
                    accessibilityLabel: "Blur radius",
                    accessibilityValue: { "\(Int($0.rounded())) pixels" }
                )
                valueLabel("\(Int(blurRadius))")
            }
        }
    }

    private func rowLabel(_ text: String) -> some View {
        Text(text)
            .font(Theme.label(12))
            .foregroundStyle(Theme.textSecondary)
            .frame(width: 52, alignment: .leading)
    }

    private func valueLabel(_ text: String) -> some View {
        Text(text)
            .font(Theme.mono(12, .semibold))
            .foregroundStyle(Theme.textPrimary)
            .frame(width: 38, alignment: .trailing)
    }

    private func select(_ kind: BackgroundStyle.Kind) {
        switch kind {
        case .none:
            commit(.none)
        case .solid:
            commit(.solidColor(NSColor(solid).cgColor))
        case .gradient:
            applyGradient()
        case .blurExtend:
            commit(.blurExtend(radius: CGFloat(blurRadius)))
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
            DispatchQueue.main.async {
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
        case .blurExtend(let radius):
            blurRadius = Double(radius)
        }
    }
}
