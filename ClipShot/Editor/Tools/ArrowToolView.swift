import AppKit
import SwiftUI

struct ArrowToolView: View {
    @ObservedObject var state: EditorState

    @State private var color = Color.red
    @State private var border = Color.white
    @State private var borderEnabled = false
    @State private var pathStyle: Annotation.ArrowPathStyle = .straight
    @State private var weight = 4.0
    @State private var isSyncing = false

    private let pathOptions: [(Annotation.ArrowPathStyle, String)] = [
        (.straight, Annotation.ArrowPathStyle.straight.displayName),
        (.curved, Annotation.ArrowPathStyle.curved.displayName)
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.panelRowSpacing) {
            HStack(spacing: 10) {
                InspectorRowLabel(text: "Path")
                HStack(spacing: 6) {
                    ForEach(pathOptions, id: \.0) { option, label in
                        ChipToggle(label: label, isOn: pathStyle == option, help: "\(label) arrow") {
                            pathStyle = option
                            apply()
                        }
                    }
                }
                Spacer()
            }
            HStack(spacing: 10) {
                InspectorRowLabel(text: "Color")
                GlassColorWell(selection: $color, label: "Arrow color")
                    .onChange(of: color) { _, _ in apply() }
            }
            HStack(spacing: 10) {
                InspectorRowLabel(text: "Border")
                GlassColorWell(selection: $border, label: "Arrow border color")
                    .opacity(borderEnabled ? 1 : 0.35)
                    .disabled(!borderEnabled)
                    .onChange(of: border) { _, _ in apply() }
                Spacer()
                Toggle("Border", isOn: $borderEnabled)
                    .labelsHidden()
                    .toggleStyle(GlassToggleStyle())
                    .onChange(of: borderEnabled) { _, _ in apply() }
            }
            HStack(spacing: 10) {
                InspectorRowLabel(text: "Weight")
                GlassSlider(
                    value: Binding(
                        get: { weight },
                        set: { newValue in
                            weight = newValue
                            apply()
                        }
                    ),
                    range: 1...18,
                    accessibilityLabel: "Arrow weight",
                    accessibilityValue: { "\(Int($0.rounded())) pixels" }
                )
                InspectorValueLabel(text: "\(Int(weight.rounded()))", suffix: "px")
            }
        }
        .onAppear { syncFromState() }
        .onChange(of: state.selectedAnnotationID) { _, _ in syncFromState() }
        .onChange(of: state.document.version) { _, _ in syncFromState() }
    }

    private func syncFromState() {
        isSyncing = true
        defer { isSyncing = false }

        if case let .arrow(_, _, selectedPathStyle, _, selectedColor, selectedWeight, selectedBorder) = state.selectedAnnotation?.kind {
            color = Color(cgColor: selectedColor)
            weight = Double(selectedWeight)
            pathStyle = selectedPathStyle
            if let selectedBorder {
                border = Color(cgColor: selectedBorder)
                borderEnabled = true
            } else {
                borderEnabled = false
                if let defaultBorder = state.toolStyle.arrowBorderColor {
                    border = Color(cgColor: defaultBorder)
                }
            }
        } else {
            color = Color(cgColor: state.toolStyle.arrowColor)
            weight = Double(state.toolStyle.arrowWeight)
            pathStyle = state.toolStyle.arrowPathStyle
            if let defaultBorder = state.toolStyle.arrowBorderColor {
                border = Color(cgColor: defaultBorder)
                borderEnabled = true
            } else {
                borderEnabled = false
            }
        }
    }

    private func apply() {
        guard !isSyncing else { return }
        let nextColor = NSColor(color).cgColor
        let nextBorder = borderEnabled ? NSColor(border).cgColor : nil
        var style = state.toolStyle
        style.arrowColor = nextColor
        style.arrowBorderColor = nextBorder
        style.arrowPathStyle = pathStyle
        style.arrowWeight = CGFloat(weight)
        state.toolStyle = style

        if case let .arrow(from, to, _, curve, _, _, _) = state.selectedAnnotation?.kind {
            let nextCurve: CGPoint?
            switch pathStyle {
            case .straight:
                nextCurve = curve
            case .curved:
                nextCurve = curve ?? AnnotationGeometry.defaultCurveControl(from: from, to: to)
            }
            state.updateSelectedKind(
                .arrow(
                    from: from,
                    to: to,
                    pathStyle: pathStyle,
                    curve: nextCurve,
                    color: nextColor,
                    weight: CGFloat(weight),
                    borderColor: nextBorder
                ),
                coalescingKey: .style
            )
        }
    }
}