import AppKit
import SwiftUI

/// Background popover: presets plus custom solid, gradient, and blur-extend controls.
struct BackgroundToolView: View {
    @ObservedObject var state: EditorState

    @State private var solid = Color.black
    @State private var gradientStart = Color(red: 0.13, green: 0.20, blue: 0.40)
    @State private var gradientEnd = Color(red: 0.55, green: 0.20, blue: 0.50)
    @State private var gradientAngle = 90.0
    @State private var blurRadius = 24.0

    private static let presets: [(name: String, style: BackgroundStyle)] = [
        ("None", .none),
        ("White", .solidColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))),
        ("Slate", .solidColor(CGColor(red: 0.11, green: 0.13, blue: 0.17, alpha: 1))),
        (
            "Ocean",
            .gradient(
                start: CGColor(red: 0.12, green: 0.36, blue: 0.72, alpha: 1),
                end: CGColor(red: 0.20, green: 0.65, blue: 0.85, alpha: 1),
                angleDegrees: 135
            )
        ),
        (
            "Sunset",
            .gradient(
                start: CGColor(red: 0.95, green: 0.45, blue: 0.25, alpha: 1),
                end: CGColor(red: 0.60, green: 0.15, blue: 0.45, alpha: 1),
                angleDegrees: 135
            )
        )
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Background")
                .font(.system(size: 13, weight: .semibold))
            presetGrid
            Divider()
            customSolid
            customGradient
            blurExtendRow
        }
        .padding(14)
        .frame(width: 260)
    }

    private var presetGrid: some View {
        let columns = Array(repeating: GridItem(.flexible(), spacing: 8), count: 5)
        return LazyVGrid(columns: columns, spacing: 8) {
            ForEach(Self.presets.indices, id: \.self) { index in
                let preset = Self.presets[index]
                Button {
                    commit(preset.style)
                } label: {
                    swatch(for: preset.style)
                        .frame(width: 34, height: 34)
                        .overlay(
                            RoundedRectangle(cornerRadius: 7, style: .continuous)
                                .stroke(Color.white.opacity(0.15))
                        )
                }
                .buttonStyle(.plain)
                .help(preset.name)
            }
        }
    }

    @ViewBuilder
    private func swatch(for style: BackgroundStyle) -> some View {
        let shape = RoundedRectangle(cornerRadius: 7, style: .continuous)
        switch style {
        case .none:
            shape
                .fill(.clear)
                .overlay(
                    Image(systemName: "circle.slash")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                )
        case .solidColor(let color):
            shape.fill(Color(cgColor: color))
        case .gradient(let start, let end, _):
            shape.fill(
                LinearGradient(
                    colors: [Color(cgColor: start), Color(cgColor: end)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
        case .blurExtend:
            shape.fill(.gray)
        }
    }

    private var customSolid: some View {
        HStack {
            Text("Solid")
                .frame(width: 70, alignment: .leading)
                .foregroundStyle(.secondary)
            ColorPicker("", selection: $solid, supportsOpacity: false)
                .labelsHidden()
            Button("Apply") {
                commit(.solidColor(NSColor(solid).cgColor))
            }
            .controlSize(.small)
        }
        .font(.system(size: 12))
    }

    private var customGradient: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Gradient")
                    .frame(width: 70, alignment: .leading)
                    .foregroundStyle(.secondary)
                ColorPicker("", selection: $gradientStart, supportsOpacity: false)
                    .labelsHidden()
                ColorPicker("", selection: $gradientEnd, supportsOpacity: false)
                    .labelsHidden()
                Button("Apply") {
                    applyGradient()
                }
                .controlSize(.small)
            }
            HStack {
                Text("Angle")
                    .frame(width: 70, alignment: .leading)
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
                    .frame(width: 28, alignment: .trailing)
                    .monospacedDigit()
            }
        }
        .font(.system(size: 12))
    }

    private var blurExtendRow: some View {
        HStack {
            Text("Blur extend")
                .frame(width: 70, alignment: .leading)
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

    private func applyGradient() {
        commit(
            .gradient(
                start: NSColor(gradientStart).cgColor,
                end: NSColor(gradientEnd).cgColor,
                angleDegrees: CGFloat(gradientAngle)
            )
        )
    }

    private func commit(_ style: BackgroundStyle) {
        state.performCommand(SetBackgroundCommand(from: state.document.background, to: style))
    }
}
