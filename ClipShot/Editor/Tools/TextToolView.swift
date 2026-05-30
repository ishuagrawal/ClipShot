import AppKit
import SwiftUI

struct TextToolView: View {
    @ObservedObject var state: EditorState

    @State private var color = Color.red
    @State private var size = 24.0
    @State private var isSyncing = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            PanelTitle(text: "Text")
            HStack(spacing: 10) {
                rowLabel("Color")
                ColorPicker("", selection: $color, supportsOpacity: false)
                    .labelsHidden()
                    .onChange(of: color) { _, _ in apply() }
            }
            HStack(spacing: 10) {
                rowLabel("Size")
                GraphiteSlider(
                    value: Binding(
                        get: { size },
                        set: { newValue in
                            size = newValue
                            apply()
                        }
                    ),
                    range: 8...96,
                    accessibilityLabel: "Font size",
                    accessibilityValue: { "\(Int($0.rounded())) points" }
                )
                valueLabel("\(Int(size.rounded()))")
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

        if case let .text(_, _, selectedSize, selectedColor) = state.selectedAnnotation?.kind {
            color = Color(cgColor: selectedColor)
            size = Double(selectedSize)
        } else {
            color = Color(cgColor: state.toolStyle.textColor)
            size = Double(state.toolStyle.textSize)
        }
    }

    private func apply() {
        guard !isSyncing else { return }
        let nextColor = NSColor(color).cgColor
        var style = state.toolStyle
        style.textColor = nextColor
        style.textSize = CGFloat(size)
        state.toolStyle = style

        if case let .text(origin, string, _, _) = state.selectedAnnotation?.kind {
            state.updateSelectedKind(
                .text(origin: origin, string: string, fontSize: CGFloat(size), color: nextColor),
                coalescingKey: .style
            )
        }
    }
}
