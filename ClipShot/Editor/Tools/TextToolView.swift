import AppKit
import SwiftUI

struct TextToolView: View {
    @ObservedObject var state: EditorState

    @State private var color = Color.red
    @State private var size = 24.0
    @State private var isSyncing = false

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.panelRowSpacing) {
            HStack(spacing: 10) {
                InspectorRowLabel(text: "Color")
                GlassColorWell(selection: $color, label: "Text color")
                    .onChange(of: color) { _, _ in apply() }
            }
            HStack(spacing: 10) {
                InspectorRowLabel(text: "Size")
                GlassSlider(
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
                InspectorValueLabel(text: "\(Int(size.rounded()))")
            }
        }
        .onAppear { syncFromState() }
        .onChange(of: state.selectedAnnotationID) { _, _ in syncFromState() }
        .onChange(of: state.document.version) { _, _ in syncFromState() }
    }

    private func syncFromState() {
        isSyncing = true
        defer { isSyncing = false }

        if case let .text(_, _, selectedSize, selectedColor) = state.selectedAnnotation?.kind {
            color = Color(cgColor: selectedColor)
            size = Double(selectedSize)
        } else if case let .text(_, _, selectedSize, selectedColor) = state.inProgressTextDraft?.kind {
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
        } else if state.inProgressTextDraft != nil {
            state.updateTextDraftStyle(fontSize: CGFloat(size), color: nextColor)
        }
    }
}
