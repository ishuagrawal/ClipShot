import AppKit
import SwiftUI

struct ArrowToolView: View {
    @ObservedObject var state: EditorState

    @State private var color = Color.red
    @State private var border = Color.white
    @State private var borderEnabled = false
    @State private var weight = 4.0
    @State private var isSyncing = false

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.panelRowSpacing) {
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

        if case let .arrow(_, _, selectedColor, selectedWeight, selectedBorder) = state.selectedAnnotation?.kind {
            color = Color(cgColor: selectedColor)
            weight = Double(selectedWeight)
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
        style.arrowWeight = CGFloat(weight)
        state.toolStyle = style

        if case let .arrow(from, to, _, _, _) = state.selectedAnnotation?.kind {
            state.updateSelectedKind(
                .arrow(
                    from: from,
                    to: to,
                    color: nextColor,
                    weight: CGFloat(weight),
                    borderColor: nextBorder
                ),
                coalescingKey: .style
            )
        }
    }
}