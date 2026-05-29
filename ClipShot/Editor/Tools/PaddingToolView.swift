import SwiftUI

/// Padding detail panel with linked and per-side box-model controls.
struct PaddingToolView: View {
    @ObservedObject var state: EditorState
    @State private var editStart: PaddingConfig?
    @State private var linked: Bool = true

    private let range: ClosedRange<Double> = 0...256

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header
            boxModel
            uniformRow
        }
        .padding(16)
        .onAppear { linked = padding.isLinked }
    }

    private var padding: PaddingConfig { state.document.padding }

    private var header: some View {
        HStack {
            PanelTitle(text: "Padding")
            Spacer()
            Button {
                linked.toggle()
                if linked {
                    commit(.uniform(padding.top))
                }
            } label: {
                Image(systemName: linked ? "link" : "link.slash")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(linked ? Theme.accent : Theme.textTertiary)
                    .frame(width: 26, height: 24)
                    .background {
                        if linked {
                            RoundedRectangle(cornerRadius: Theme.radiusSmall, style: .continuous)
                                .fill(Color.clear)
                                .raised(cornerRadius: Theme.radiusSmall)
                                .overlay(
                                    RoundedRectangle(cornerRadius: Theme.radiusSmall, style: .continuous)
                                        .fill(Theme.accentDim)
                                )
                        }
                    }
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(linked ? "Sides linked" : "Sides independent")
        }
    }

    private var boxModel: some View {
        VStack(spacing: 7) {
            field(.top)
            HStack(spacing: 7) {
                field(.left)
                Color.clear
                    .frame(height: 54)
                    .recessed(cornerRadius: Theme.radiusSmall)
                    .overlay(
                        Image(systemName: "photo")
                            .font(.system(size: 15))
                            .foregroundStyle(Theme.textTertiary)
                    )
                field(.right)
            }
            field(.bottom)
        }
    }

    private func field(_ side: PaddingSide) -> some View {
        TextField(
            "",
            value: Binding(
                get: { Int(value(of: side)) },
                set: { setSide(side, to: CGFloat($0)) }
            ),
            format: .number
        )
        .textFieldStyle(.plain)
        .font(Theme.mono(12, .semibold))
        .foregroundStyle(Theme.textPrimary)
        .multilineTextAlignment(.center)
        .frame(width: 54)
        .padding(.vertical, 6)
        .recessed(cornerRadius: Theme.radiusSmall)
        .accessibilityLabel(label(side))
    }

    private var uniformRow: some View {
        VStack(alignment: .leading, spacing: 9) {
            PanelTitle(text: "Uniform")
            HStack(spacing: 10) {
                GraphiteSlider(
                value: Binding(
                    get: { Double(padding.uniform ?? padding.top) },
                    set: { value in
                        linked = true
                        setLive(.uniform(CGFloat(value.rounded())))
                    }
                ),
                range: range,
                accessibilityLabel: "Uniform padding",
                accessibilityValue: { "\(Int($0.rounded())) pixels" },
                onEditingChanged: { editing in
                    if editing {
                        editStart = padding
                    } else {
                        commitDrag()
                    }
                }
            )
                Text("\(Int(padding.uniform ?? padding.top))")
                    .font(Theme.mono(12, .semibold))
                    .foregroundStyle(Theme.textPrimary)
                    .frame(width: 30, alignment: .trailing)
            }
        }
    }

    private func value(of side: PaddingSide) -> CGFloat {
        switch side {
        case .top:
            return padding.top
        case .right:
            return padding.right
        case .bottom:
            return padding.bottom
        case .left:
            return padding.left
        }
    }

    private func label(_ side: PaddingSide) -> String {
        switch side {
        case .top:
            return "Top padding"
        case .right:
            return "Right padding"
        case .bottom:
            return "Bottom padding"
        case .left:
            return "Left padding"
        }
    }

    private func setSide(_ side: PaddingSide, to value: CGFloat) {
        let next = linked ? PaddingConfig.uniform(value) : padding.setting(side, to: value)
        commit(next)
    }

    private func setLive(_ next: PaddingConfig) {
        if editStart == nil {
            editStart = padding
        }
        state.document.padding = next.clamped()
    }

    private func commit(_ next: PaddingConfig) {
        let from = padding
        state.performCommand(SetPaddingCommand(from: from, to: next.clamped()))
    }

    private func commitDrag() {
        guard let from = editStart else { return }
        let to = padding
        state.document.padding = from
        state.performCommand(SetPaddingCommand(from: from, to: to.clamped()))
        editStart = nil
    }
}
