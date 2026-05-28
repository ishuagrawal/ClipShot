import SwiftUI

/// Padding detail panel with linked and per-side box-model controls.
struct PaddingToolView: View {
    @ObservedObject var state: EditorState
    @State private var editStart: PaddingConfig?
    @State private var linked: Bool = true

    private let range: ClosedRange<Double> = 0...256

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            boxModel
            uniformSlider
        }
        .padding(14)
        .onAppear { linked = padding.isLinked }
    }

    private var padding: PaddingConfig { state.document.padding }

    private var header: some View {
        HStack {
            Text("Padding")
                .font(.system(size: 13, weight: .semibold))
            Spacer()
            Button {
                linked.toggle()
                if linked {
                    commit(.uniform(padding.top))
                }
            } label: {
                Image(systemName: linked ? "link" : "link.slash")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(linked ? Color.blue : Color.white.opacity(0.5))
            }
            .buttonStyle(.plain)
            .help(linked ? "Sides linked" : "Sides independent")
        }
    }

    private var boxModel: some View {
        VStack(spacing: 6) {
            field(.top)
            HStack(spacing: 6) {
                field(.left)
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Color.white.opacity(0.08))
                    .overlay(
                        Image(systemName: "photo")
                            .font(.system(size: 16))
                            .foregroundStyle(.secondary)
                    )
                    .frame(height: 56)
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
        .frame(width: 52)
        .multilineTextAlignment(.center)
        .textFieldStyle(.roundedBorder)
        .accessibilityLabel(label(side))
    }

    private var uniformSlider: some View {
        Slider(
            value: Binding(
                get: { Double(padding.uniform ?? padding.top) },
                set: { value in
                    linked = true
                    setLive(.uniform(CGFloat(value.rounded())))
                }
            ),
            in: range,
            onEditingChanged: { editing in
                if editing {
                    editStart = padding
                } else {
                    commitDrag()
                }
            }
        )
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
