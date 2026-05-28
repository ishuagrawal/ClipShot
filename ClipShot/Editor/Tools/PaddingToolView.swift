import SwiftUI

/// Padding popover: whole-pixel uniform control plus per-side overrides.
struct PaddingToolView: View {
    @ObservedObject var state: EditorState
    @State private var showsPerSide = false
    @State private var editStart: PaddingConfig?

    private let range: ClosedRange<Double> = 0...256

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Padding")
                .font(.system(size: 13, weight: .semibold))
            uniformRow
            DisclosureGroup("Per side", isExpanded: $showsPerSide) {
                VStack(spacing: 8) {
                    sideRow("Top", get: { $0.top }, set: { $0.top = $1 })
                    sideRow("Right", get: { $0.right }, set: { $0.right = $1 })
                    sideRow("Bottom", get: { $0.bottom }, set: { $0.bottom = $1 })
                    sideRow("Left", get: { $0.left }, set: { $0.left = $1 })
                }
                .padding(.top, 6)
            }
            .font(.system(size: 12))
        }
        .padding(14)
        .frame(width: 240)
    }

    private var uniformValue: Double {
        Double(state.document.padding.uniform ?? state.document.padding.top)
    }

    private var uniformRow: some View {
        HStack(spacing: 8) {
            Slider(
                value: Binding(
                    get: { uniformValue },
                    set: { setLiveUniform(CGFloat($0.rounded())) }
                ),
                in: range,
                onEditingChanged: { onEditing($0) }
            )
            TextField(
                "",
                value: Binding(
                    get: { Int(uniformValue) },
                    set: { commitUniform(CGFloat($0)) }
                ),
                format: .number
            )
            .frame(width: 44)
            .multilineTextAlignment(.trailing)
            .textFieldStyle(.roundedBorder)
        }
    }

    private func sideRow(
        _ label: String,
        get: @escaping (PaddingConfig) -> CGFloat,
        set: @escaping (inout PaddingConfig, CGFloat) -> Void
    ) -> some View {
        HStack {
            Text(label)
                .frame(width: 54, alignment: .leading)
                .foregroundStyle(.secondary)
            Slider(
                value: Binding(
                    get: { Double(get(state.document.padding)) },
                    set: { value in
                        var padding = state.document.padding
                        set(&padding, CGFloat(value.rounded()))
                        setLive(padding)
                    }
                ),
                in: range,
                onEditingChanged: { onEditing($0) }
            )
            TextField(
                "",
                value: Binding(
                    get: { Int(get(state.document.padding)) },
                    set: { value in
                        var padding = state.document.padding
                        set(&padding, CGFloat(value))
                        commit(padding)
                    }
                ),
                format: .number
            )
            .frame(width: 44)
            .multilineTextAlignment(.trailing)
            .textFieldStyle(.roundedBorder)
        }
    }

    private func onEditing(_ editing: Bool) {
        if editing {
            editStart = state.document.padding
        } else {
            commitDrag()
        }
    }

    private func setLiveUniform(_ value: CGFloat) {
        setLive(PaddingConfig(top: value, right: value, bottom: value, left: value))
    }

    private func setLive(_ padding: PaddingConfig) {
        if editStart == nil {
            editStart = state.document.padding
        }
        state.document.padding = padding.clamped()
    }

    private func commit(_ padding: PaddingConfig) {
        let from = editStart ?? state.document.padding
        state.document.padding = from
        state.performCommand(SetPaddingCommand(from: from, to: padding.clamped()))
        editStart = nil
    }

    private func commitUniform(_ value: CGFloat) {
        commit(PaddingConfig(top: value, right: value, bottom: value, left: value))
    }

    private func commitDrag() {
        guard let from = editStart else { return }
        let to = state.document.padding
        state.document.padding = from
        state.performCommand(SetPaddingCommand(from: from, to: to))
        editStart = nil
    }
}

private extension PaddingConfig {
    func clamped() -> PaddingConfig {
        func clamp(_ value: CGFloat) -> CGFloat {
            min(max(value, 0), 256)
        }
        return PaddingConfig(
            top: clamp(top),
            right: clamp(right),
            bottom: clamp(bottom),
            left: clamp(left)
        )
    }
}
