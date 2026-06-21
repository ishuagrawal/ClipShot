import AppKit
import SwiftUI

struct ArrowToolView: View {
    @ObservedObject var state: EditorState

    @State private var color = Color.red
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

        if case let .arrow(_, _, selectedColor, selectedWeight) = state.selectedAnnotation?.kind {
            color = Color(cgColor: selectedColor)
            weight = Double(selectedWeight)
        } else {
            color = Color(cgColor: state.toolStyle.arrowColor)
            weight = Double(state.toolStyle.arrowWeight)
        }
    }

    private func apply() {
        guard !isSyncing else { return }
        let nextColor = NSColor(color).cgColor
        var style = state.toolStyle
        style.arrowColor = nextColor
        style.arrowWeight = CGFloat(weight)
        state.toolStyle = style

        if case let .arrow(from, to, _, _) = state.selectedAnnotation?.kind {
            state.updateSelectedKind(
                .arrow(from: from, to: to, color: nextColor, weight: CGFloat(weight)),
                coalescingKey: .style
            )
        }
    }
}
