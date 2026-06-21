import AppKit
import SwiftUI

struct RectangleToolView: View {
    @ObservedObject var state: EditorState

    @State private var stroke = Color.red
    @State private var fill = Color.red.opacity(0.24)
    @State private var fillEnabled = false
    @State private var weight = 3.0
    @State private var corner = 6.0
    @State private var isSyncing = false

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.panelRowSpacing) {
            HStack(spacing: 10) {
                InspectorRowLabel(text: "Stroke")
                GlassColorWell(selection: $stroke, label: "Stroke color")
                    .onChange(of: stroke) { _, _ in apply() }
            }
            HStack(spacing: 10) {
                InspectorRowLabel(text: "Fill")
                Toggle("Fill", isOn: $fillEnabled)
                    .labelsHidden()
                    .toggleStyle(GlassToggleStyle())
                    .onChange(of: fillEnabled) { _, _ in apply() }
                GlassColorWell(selection: $fill, supportsOpacity: true, label: "Fill color")
                    .opacity(fillEnabled ? 1 : 0.35)
                    .disabled(!fillEnabled)
                    .onChange(of: fill) { _, _ in apply() }
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
                    accessibilityLabel: "Rectangle stroke weight",
                    accessibilityValue: { "\(Int($0.rounded())) pixels" }
                )
                InspectorValueLabel(text: "\(Int(weight.rounded()))", suffix: "px")
            }
            HStack(spacing: 10) {
                InspectorRowLabel(text: "Corner")
                GlassSlider(
                    value: Binding(
                        get: { corner },
                        set: { newValue in
                            corner = newValue
                            apply()
                        }
                    ),
                    range: 0...36,
                    accessibilityLabel: "Rectangle corner radius",
                    accessibilityValue: { "\(Int($0.rounded())) pixels" }
                )
                InspectorValueLabel(text: "\(Int(corner.rounded()))", suffix: "px")
            }
        }
        .onAppear { syncFromState() }
        .onChange(of: state.selectedAnnotationID) { _, _ in syncFromState() }
        .onChange(of: state.document.version) { _, _ in syncFromState() }
    }

    private func syncFromState() {
        isSyncing = true
        defer { isSyncing = false }

        if case let .rect(_, selectedStroke, selectedFill, selectedWeight, selectedCorner) = state.selectedAnnotation?.kind {
            stroke = Color(cgColor: selectedStroke ?? state.toolStyle.rectStroke ?? CGColor(gray: 1, alpha: 1))
            if let selectedFill {
                fill = Color(cgColor: selectedFill)
                fillEnabled = true
            } else {
                fillEnabled = false
                if let defaultFill = state.toolStyle.rectFill {
                    fill = Color(cgColor: defaultFill)
                }
            }
            weight = Double(selectedWeight)
            corner = Double(selectedCorner)
        } else {
            stroke = Color(cgColor: state.toolStyle.rectStroke ?? CGColor(gray: 1, alpha: 1))
            if let defaultFill = state.toolStyle.rectFill {
                fill = Color(cgColor: defaultFill)
                fillEnabled = true
            } else {
                fillEnabled = false
            }
            weight = Double(state.toolStyle.rectWeight)
            corner = Double(state.toolStyle.rectCorner)
        }
    }

    private func apply() {
        guard !isSyncing else { return }
        let strokeColor = NSColor(stroke).cgColor
        let fillColor = fillEnabled ? NSColor(fill).cgColor : nil
        var style = state.toolStyle
        style.rectStroke = strokeColor
        style.rectFill = fillColor
        style.rectWeight = CGFloat(weight)
        style.rectCorner = CGFloat(corner)
        state.toolStyle = style

        if case let .rect(frame, _, _, _, _) = state.selectedAnnotation?.kind {
            state.updateSelectedKind(
                .rect(
                    frame: frame,
                    stroke: strokeColor,
                    fill: fillColor,
                    weight: CGFloat(weight),
                    cornerRadius: CGFloat(corner)
                ),
                coalescingKey: .style
            )
        }
    }
}
