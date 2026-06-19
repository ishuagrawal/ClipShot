import AppKit
import SwiftUI

struct LineToolView: View {
    @ObservedObject var state: EditorState

    @State private var color = Color.red
    @State private var weight = 4.0
    @State private var dash: Annotation.LineDash = .solid
    @State private var isSyncing = false

    private let dashOptions: [(Annotation.LineDash, String)] = [
        (.solid, "Solid"),
        (.dashed, "Dashed"),
        (.dotted, "Dotted")
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.panelRowSpacing) {
            HStack(spacing: 10) {
                InspectorRowLabel(text: "Color")
                GlassColorWell(selection: $color, label: "Line color")
                    .onChange(of: color) { _, _ in apply() }
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
                    accessibilityLabel: "Line weight",
                    accessibilityValue: { "\(Int($0.rounded())) pixels" }
                )
                InspectorValueLabel(text: "\(Int(weight.rounded()))")
            }
            HStack(spacing: 10) {
                InspectorRowLabel(text: "Style")
                HStack(spacing: 6) {
                    ForEach(dashOptions, id: \.0) { option, label in
                        ChipToggle(label: label, isOn: dash == option, help: "\(label) line") {
                            dash = option
                            apply()
                        }
                    }
                }
                Spacer()
            }
        }
        .onAppear { syncFromState() }
        .onChange(of: state.selectedAnnotationID) { _, _ in syncFromState() }
        .onChange(of: state.document.version) { _, _ in syncFromState() }
    }

    private func syncFromState() {
        isSyncing = true
        defer { isSyncing = false }

        if case let .line(_, _, selectedColor, selectedWeight, selectedDash) = state.selectedAnnotation?.kind {
            color = Color(cgColor: selectedColor)
            weight = Double(selectedWeight)
            dash = selectedDash
        } else {
            color = Color(cgColor: state.toolStyle.lineColor)
            weight = Double(state.toolStyle.lineWeight)
            dash = state.toolStyle.lineDash
        }
    }

    private func apply() {
        guard !isSyncing else { return }
        let nextColor = NSColor(color).cgColor
        var style = state.toolStyle
        style.lineColor = nextColor
        style.lineWeight = CGFloat(weight)
        style.lineDash = dash
        state.toolStyle = style

        if case let .line(from, to, _, _, _) = state.selectedAnnotation?.kind {
            state.updateSelectedKind(
                .line(from: from, to: to, color: nextColor, weight: CGFloat(weight), dash: dash),
                coalescingKey: .style
            )
        }
    }
}
