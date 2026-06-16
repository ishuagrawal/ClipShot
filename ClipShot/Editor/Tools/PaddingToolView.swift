import AppKit
import SwiftUI

/// Padding detail panel with linked and per-side box-model controls.
struct PaddingToolView: View {
    @ObservedObject var state: EditorState
    @State private var editStart: PaddingConfig?
    @State private var linked: Bool = true
    @State private var cornerEditing: Bool = false
    @State private var cornerStart: CGFloat?
    @State private var shotCornerEditing: Bool = false
    @State private var shotCornerStart: CGFloat?
    @State private var shadowColor = Color(cgColor: ShadowConfig.default.color)
    @State private var syncingShadow = false
    @State private var isCentering = false

    private let paddingRange: ClosedRange<Double> = 0...Double(PaddingConfig.maximum)

    private var cardCornerRange: ClosedRange<Double> {
        0...max(1, Double(state.document.maxCardCornerRadius.rounded(.down)))
    }

    private var screenshotCornerRange: ClosedRange<Double> {
        let maximum = min(state.document.baseSelection.width, state.document.baseSelection.height) / 2
        return 0...max(1, Double(maximum.rounded(.down)))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.panelSectionSpacing) {
            VStack(alignment: .leading, spacing: Theme.panelRowSpacing) {
                header
                boxModel
            }
            uniformRow
            cornerRow
            screenshotCornerRow
            shadowSection
        }
        .onAppear {
            linked = padding.isLinked
            shadowColor = Color(cgColor: state.document.shadow.color)
        }
        .onChange(of: state.document.shadow) { _, newShadow in
            syncingShadow = true
            shadowColor = Color(cgColor: newShadow.color)
            Task { @MainActor in syncingShadow = false }
        }
    }

    private var padding: PaddingConfig { state.document.padding }

    private var header: some View {
        HStack {
            ChipToggle(
                label: "Auto",
                systemName: "wand.and.stars",
                isOn: true,
                isMomentary: true,
                help: "Auto padding + background"
            ) { applyAuto() }
            ChipToggle(
                label: "Center",
                systemName: isCentering ? "circle.dotted" : "rectangle.center.inset.filled",
                isOn: true,
                isMomentary: true,
                help: "Crop to content and center with equal margins"
            ) { applyAutoCenter() }
            ChipToggle(
                systemName: linked ? "link" : "link.slash",
                isOn: linked,
                help: linked ? "Sides linked" : "Sides independent"
            ) {
                linked.toggle()
                if linked {
                    commit(.uniform(padding.top))
                }
            }
            Spacer()
        }
    }

    /// Frame diagram: the artboard floats in the middle of a carved well, the four
    /// per-side values orbit it as mono pills. Reads as a diagram, not a form.
    private var boxModel: some View {
        VStack(spacing: 6) {
            field(.top)
            HStack(spacing: 6) {
                field(.left)
                artboardGlyph
                field(.right)
            }
            field(.bottom)
        }
        .frame(maxWidth: .infinity)
    }

    private var artboardGlyph: some View {
        RoundedRectangle(cornerRadius: 9, style: .continuous)
            .fill(Color.black.opacity(0.30))
            .overlay(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .stroke(Theme.hairline, lineWidth: 1)
            )
            .overlay(
                // The capture inside its padding, drawn as a glyph.
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .strokeBorder(Theme.accentText.opacity(0.85), lineWidth: 1.5)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 13)
            )
            .frame(height: 52)
            .accessibilityHidden(true)
    }

    private func field(_ side: PaddingSide) -> some View {
        TextField(
            "",
            text: Binding(
                get: { "\(Int(value(of: side).rounded()))" },
                set: { rawValue in
                    if let value = parsePadding(rawValue) {
                        setSide(side, to: CGFloat(value))
                    }
                }
            ),
            prompt: Text("")
        )
        .textFieldStyle(.plain)
        .font(Theme.mono(12, .semibold))
        .foregroundStyle(Theme.textPrimary)
        .multilineTextAlignment(.center)
        .frame(width: 54)
        .padding(.vertical, 5)
        .background(Capsule().fill(Color.black.opacity(0.30)))
        .overlay(Capsule().stroke(Color.white.opacity(0.12), lineWidth: 1))
        .accessibilityLabel(label(side))
    }

    private var uniformRow: some View {
        PanelSection("Uniform") {
            HStack(spacing: 10) {
                GlassSlider(
                value: Binding(
                    get: { Double(padding.uniform ?? padding.top) },
                    set: { value in
                        linked = true
                        setLive(.uniform(CGFloat(value.rounded())))
                    }
                ),
                range: paddingRange,
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
                InspectorValueLabel(text: "\(Int(padding.uniform ?? padding.top))")
            }
        }
    }

    private var cornerRow: some View {
        PanelSection("Corner radius") {
            ChipToggle(
                label: "Concentric",
                isOn: isConcentricCorner,
                help: "Match the screenshot corners (concentric)"
            ) { applyConcentricCorner() }
        } content: {
            HStack(spacing: 10) {
                GlassSlider(
                    value: Binding(
                        get: { Double(state.document.cardCornerRadius ?? 0) },
                        set: { setLiveCorner(CGFloat($0.rounded())) }
                    ),
                    range: cardCornerRange,
                    accessibilityLabel: "Corner radius",
                    accessibilityValue: { "\(Int($0.rounded())) pixels" },
                    onEditingChanged: { editing in
                        if editing {
                            cornerEditing = true
                            cornerStart = state.document.cardCornerOverride
                        } else {
                            commitCornerDrag()
                        }
                    }
                )
                InspectorValueLabel(text: "\(Int(state.document.cardCornerRadius ?? 0))")
            }
        }
    }

    private var isConcentricCorner: Bool { state.document.isCardCornerConcentric }

    private func setLiveCorner(_ value: CGFloat) {
        if !cornerEditing {
            cornerEditing = true
            cornerStart = state.document.cardCornerOverride
        }
        state.document.cardCornerOverride = value
    }

    private func commitCornerDrag() {
        guard cornerEditing else { return }
        let from = cornerStart
        let to = state.document.cardCornerOverride
        state.document.cardCornerOverride = from
        state.performCommand(SetCardCornerCommand(from: from, to: to))
        cornerEditing = false
        cornerStart = nil
    }

    private func applyConcentricCorner() {
        guard state.document.cardCornerOverride != nil else { return }
        state.performCommand(
            SetCardCornerCommand(from: state.document.cardCornerOverride, to: nil)
        )
    }

    // MARK: - Screenshot corners

    private var screenshotCornerRow: some View {
        PanelSection("Screenshot corners") {
            ChipToggle(
                systemName: isCornerLocked ? "lock" : "lock.open",
                isOn: isCornerLocked,
                help: "Lock the screenshot corners to the card radius"
            ) { toggleCornerLock() }
        } content: {
            HStack(spacing: 10) {
                GlassSlider(
                    value: Binding(
                        get: { Double(screenshotCornerValue) },
                        set: { setLiveShotCorner(CGFloat($0.rounded())) }
                    ),
                    range: screenshotCornerRange,
                    accessibilityLabel: "Screenshot corner radius",
                    accessibilityValue: { "\(Int($0.rounded())) pixels" },
                    onEditingChanged: { editing in
                        if editing {
                            shotCornerEditing = true
                            shotCornerStart = state.document.screenshotCornerOverride
                        } else {
                            commitShotCornerDrag()
                        }
                    }
                )
                .disabled(isCornerLocked)
                .opacity(isCornerLocked ? 0.45 : 1)
                InspectorValueLabel(text: "\(Int(screenshotCornerValue))")
            }
        }
    }

    private var isCornerLocked: Bool { state.document.lockCornersToCard }

    private var screenshotCornerValue: CGFloat {
        if state.document.lockCornersToCard { return state.document.cardCornerRadius ?? 0 }
        return state.document.effectiveSelectionCornerRadii.uniformRadius ?? 0
    }

    private func setLiveShotCorner(_ value: CGFloat) {
        guard !isCornerLocked else { return }
        if !shotCornerEditing {
            shotCornerEditing = true
            shotCornerStart = state.document.screenshotCornerOverride
        }
        state.document.screenshotCornerOverride = value
    }

    private func commitShotCornerDrag() {
        guard shotCornerEditing else { return }
        let from = shotCornerStart
        let to = state.document.screenshotCornerOverride
        state.document.screenshotCornerOverride = from
        state.performCommand(
            SetScreenshotCornerCommand(
                fromRadius: from, toRadius: to,
                fromLock: state.document.lockCornersToCard,
                toLock: state.document.lockCornersToCard
            )
        )
        shotCornerEditing = false
        shotCornerStart = nil
    }

    private func toggleCornerLock() {
        let doc = state.document
        let newLock = !doc.lockCornersToCard
        // Seed the override on unlock to whatever was displayed while locked (the card
        // radius), so the screenshot corners don't jump back to the captured value.
        let newOverride: CGFloat? = newLock
            ? doc.screenshotCornerOverride
            : (doc.cardCornerRadius ?? doc.screenshotCornerOverride ?? doc.effectiveSelectionCornerRadii.uniformRadius)
        state.performCommand(
            SetScreenshotCornerCommand(
                fromRadius: doc.screenshotCornerOverride, toRadius: newOverride,
                fromLock: doc.lockCornersToCard, toLock: newLock
            )
        )
    }

    // MARK: - Shadow

    private var shadow: ShadowConfig { state.document.shadow }

    private var shadowSection: some View {
        PanelSection("Shadow") {
            Toggle("Shadow", isOn: Binding(
                get: { shadow.isEnabled },
                set: { var next = shadow; next.isEnabled = $0; commitShadow(next) }
            ))
            .labelsHidden()
            .toggleStyle(GlassToggleStyle())
        } content: {
            if shadow.isEnabled {
                shadowSlider("Blur", value: shadow.blur, range: 0...Double(ShadowConfig.maximumBlur)) {
                    var next = shadow; next.blur = $0; commitShadow(next)
                }
                shadowSlider(
                    "Offset X",
                    value: shadow.offsetX,
                    range: -Double(ShadowConfig.maximumOffset)...Double(ShadowConfig.maximumOffset)
                ) {
                    var next = shadow; next.offsetX = $0; commitShadow(next)
                }
                shadowSlider(
                    "Offset Y",
                    value: shadow.offsetY,
                    range: -Double(ShadowConfig.maximumOffset)...Double(ShadowConfig.maximumOffset)
                ) {
                    var next = shadow; next.offsetY = $0; commitShadow(next)
                }
                shadowSlider(
                    "Opacity",
                    value: shadow.opacity * 100,
                    range: 0...Double(ShadowConfig.maximumOpacity * 100),
                    suffix: "%"
                ) {
                    var next = shadow; next.opacity = $0 / 100; commitShadow(next)
                }
                HStack {
                    InspectorRowLabel(text: "Color")
                    GlassColorWell(selection: $shadowColor, label: "Shadow color")
                        .onChange(of: shadowColor) { _, newColor in
                            guard !syncingShadow else { return }
                            var next = shadow
                            next.color = NSColor(newColor).cgColor
                            commitShadow(next)
                        }
                    Spacer()
                }
            }
        }
    }

    private func shadowSlider(
        _ label: String,
        value: CGFloat,
        range: ClosedRange<Double>,
        suffix: String = "",
        _ set: @escaping (CGFloat) -> Void
    ) -> some View {
        HStack(spacing: 10) {
            InspectorRowLabel(text: label)
            GlassSlider(
                value: Binding(get: { Double(value) }, set: { set(CGFloat($0.rounded())) }),
                range: range,
                accessibilityLabel: label,
                accessibilityValue: { "\(Int($0.rounded()))\(suffix)" }
            )
            InspectorValueLabel(text: "\(Int(value))", suffix: suffix)
        }
    }

    private func commitShadow(_ next: ShadowConfig) {
        let clamped = next.clamped
        guard clamped != shadow else { return }
        state.performCommand(SetShadowCommand(from: shadow, to: clamped))
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

    private func parsePadding(_ rawValue: String) -> Int? {
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let value = Int(trimmed) else { return nil }
        return value
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

    private func applyAuto() {
        let auto = PaddingConfig.autoSweetSpot(forSelection: state.document.baseSelection.size)
        let currentBackground = state.document.background
        let autoBackground = currentBackground == .none ? .dynamic : currentBackground
        linked = true
        state.performCommand(
            ApplyAutoPaddingCommand(
                fromPadding: padding,
                toPadding: auto.clamped(),
                fromBackground: currentBackground,
                toBackground: autoBackground
            )
        )
    }

    private func applyAutoCenter() {
        guard !isCentering else { return }
        isCentering = true
        let image = state.document.screenshot
        let region = state.document.baseSelection
        let fromPadding = state.document.padding
        Task.detached(priority: .userInitiated) {
            let bbox = ContentBoundsDetector().detect(in: image, region: region)
            await MainActor.run {
                isCentering = false
                guard let bbox else { return }
                let toPadding = resolvedUniformPadding(fromPadding, bboxSize: bbox.size)
                guard bbox != region || toPadding != fromPadding else { return }
                linked = true
                state.performCommand(
                    ApplyAutoCenterCommand(
                        fromSelection: region,
                        toSelection: bbox,
                        fromPadding: fromPadding,
                        toPadding: toPadding
                    )
                )
            }
        }
    }

    /// Equal margins on all sides: keep the user's uniform amount if they set one,
    /// otherwise fall back to the size-derived sweet spot.
    private func resolvedUniformPadding(_ current: PaddingConfig, bboxSize: CGSize) -> PaddingConfig {
        if let uniform = current.uniform, uniform > 0 {
            return current
        }
        return PaddingConfig.autoSweetSpot(forSelection: bboxSize).clamped()
    }

    private func commitDrag() {
        guard let from = editStart else { return }
        let to = padding
        state.document.padding = from
        state.performCommand(SetPaddingCommand(from: from, to: to.clamped()))
        editStart = nil
    }
}
