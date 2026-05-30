import AppKit
import SwiftUI

struct ArrowToolView: View {
    @ObservedObject var state: EditorState

    @State private var color = Color.red
    @State private var weight = 4.0
    @State private var isSyncing = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            PanelTitle(text: "Arrow")
            HStack(spacing: 10) {
                rowLabel("Color")
                ColorPicker("", selection: $color, supportsOpacity: false)
                    .labelsHidden()
                    .onChange(of: color) { _, _ in apply() }
            }
            HStack(spacing: 10) {
                rowLabel("Weight")
                GraphiteSlider(
                    value: $weight,
                    range: 1...18,
                    accessibilityLabel: "Arrow weight",
                    accessibilityValue: { "\(Int($0.rounded())) pixels" },
                    onEditingChanged: { if !$0 { apply() } }
                )
                valueLabel("\(Int(weight.rounded()))")
            }
        }
        .padding(16)
        .onAppear { syncFromState() }
        .onChange(of: state.selectedAnnotationID) { _, _ in syncFromState() }
        .onChange(of: state.document.version) { _, _ in syncFromState() }
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
            .frame(width: 34, alignment: .trailing)
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
                .arrow(from: from, to: to, color: nextColor, weight: CGFloat(weight))
            )
        }
    }
}
