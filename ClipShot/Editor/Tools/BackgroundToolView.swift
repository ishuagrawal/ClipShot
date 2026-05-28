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
        VStack(alignment: .leading, spacing: 14) {
            Text("Background")
                .font(.system(size: 13, weight: .semibold))
            tiles
            Divider()
            config
        }
        .padding(14)
        .onAppear { syncControls(from: style) }
        .onChange(of: style) { _, newStyle in
            syncControls(from: newStyle)
        }
    }

    private var tiles: some View {
        HStack(spacing: 8) {
            ForEach(BackgroundStyle.Kind.allCases, id: \.self) { kind in
                Button {
                    select(kind)
                } label: {
                    tileSwatch(kind)
                        .frame(width: 40, height: 40)
                        .overlay(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .stroke(
                                    style.kind == kind ? Color.blue : Color.white.opacity(0.15),
                                    lineWidth: style.kind == kind ? 2 : 1
                                )
                        )
                }
                .buttonStyle(.plain)
                .help(tileName(kind))
            }
        }
    }

    @ViewBuilder
    private func tileSwatch(_ kind: BackgroundStyle.Kind) -> some View {
        let shape = RoundedRectangle(cornerRadius: 8, style: .continuous)
        switch kind {
        case .none:
            shape
                .fill(.clear)
                .overlay(
                    Image(systemName: "circle.slash")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
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
                .fill(.gray)
                .overlay(
                    Image(systemName: "drop.halffull")
                        .font(.system(size: 13))
                        .foregroundStyle(.white.opacity(0.7))
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
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
        case .solid:
            HStack {
                Text("Color")
                    .frame(width: 60, alignment: .leading)
                    .foregroundStyle(.secondary)
                ColorPicker("", selection: $solid, supportsOpacity: false)
                    .labelsHidden()
                    .onChange(of: solid) { _, _ in
                        guard !isSyncingControls else { return }
                        commit(.solidColor(NSColor(solid).cgColor))
                    }
            }
            .font(.system(size: 12))
        case .gradient:
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Colors")
                        .frame(width: 60, alignment: .leading)
                        .foregroundStyle(.secondary)
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
                HStack {
                    Text("Angle")
                        .frame(width: 60, alignment: .leading)
                        .foregroundStyle(.secondary)
                    Slider(
                        value: $gradientAngle,
                        in: 0...360,
                        onEditingChanged: { editing in
                            if !editing {
                                applyGradient()
                            }
                        }
                    )
                    Text("\(Int(gradientAngle))")
                        .frame(width: 34, alignment: .trailing)
                        .monospacedDigit()
                }
            }
            .font(.system(size: 12))
        case .blurExtend:
            HStack {
                Text("Radius")
                    .frame(width: 60, alignment: .leading)
                    .foregroundStyle(.secondary)
                Slider(
                    value: $blurRadius,
                    in: 0...80,
                    onEditingChanged: { editing in
                        if !editing {
                            commit(.blurExtend(radius: CGFloat(blurRadius)))
                        }
                    }
                )
                Text("\(Int(blurRadius))")
                    .frame(width: 30, alignment: .trailing)
                    .monospacedDigit()
            }
            .font(.system(size: 12))
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
