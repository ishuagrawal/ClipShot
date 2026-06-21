import AppKit
import SwiftUI

/// Padding detail panel with per-side box-model controls.
struct PaddingToolView: View {
    @ObservedObject var state: EditorState
    @State private var editStart: PaddingConfig?
    @State private var cornerEditing: Bool = false
    @State private var cornerStart: CGFloat?
    @State private var shotCornerEditing: Bool = false
    @State private var shotCornerStart: CGFloat?
    @State private var shadowColor = Color(cgColor: ShadowConfig.default.color)
    @State private var syncingShadow = false
    @State private var isCentering = false
    @State private var insetDragStart: (
        screenshot: CGImage,
        selection: CGRect,
        padding: PaddingConfig,
        shift: CGSize,
        context: EditorState.AutoCenterContext
    )?

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
            insetRow
            cornerRow
            screenshotCornerRow
            shadowSection
        }
        .onAppear {
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
                label: "Center",
                systemName: isCentering ? "circle.dotted" : "rectangle.center.inset.filled",
                isOn: false,
                isMomentary: true,
                ghostAccent: true,
                help: "Trim to content and center with equal inset"
            ) { applyAutoCenter() }
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
                InspectorValueLabel(text: "\(Int(padding.uniform ?? padding.top))", suffix: "px")
            }
        }
    }

    /// The auto-center context, but only while it still matches the on-screen card.
    /// A screenshot swapped by undo or another tool invalidates it.
    private var activeInsetContext: EditorState.AutoCenterContext? {
        guard let context = state.autoCenter,
              state.document.screenshot === context.card else { return nil }
        return context
    }

    private var insetRange: ClosedRange<Double> {
        guard let context = activeInsetContext else { return 0...96 }
        let maxSide = Double(max(context.content.width, context.content.height))
        return 0...max(96, (maxSide * 0.5).rounded())
    }

    /// Inset band inside the centered card. Drags recompose the card live from
    /// the trimmed content; the original screenshot is never re-trimmed.
    private var insetRow: some View {
        PanelSection("Inset") {
            HStack(spacing: 10) {
                GlassSlider(
                    value: Binding(
                        get: { Double(activeInsetContext?.inset ?? 0) },
                        set: { setLiveInset(CGFloat($0.rounded())) }
                    ),
                    range: insetRange,
                    accessibilityLabel: "Inset",
                    accessibilityValue: { "\(Int($0.rounded())) pixels" },
                    onEditingChanged: { editing in
                        if !editing { commitInsetDrag() }
                    }
                )
                InspectorValueLabel(text: "\(Int(activeInsetContext?.inset ?? 0))", suffix: "px")
            }
        }
    }

    /// Seed an inset context that adds an equal band around the screenshot as-is —
    /// no trim, no recenter (that is the center button's job). Detection supplies
    /// only the band fill color so the whitespace blends with the background.
    private func ensureInsetContext() -> EditorState.AutoCenterContext? {
        if let context = activeInsetContext { return context }
        let image = state.document.screenshot
        let region = state.document.baseSelection
        guard let contentImage = image.cropping(to: region.integral) else { return nil }
        let fill = ContentBoundsDetector().detect(in: image, region: region)?.fillColor
            ?? CGColor(gray: 1, alpha: 1)
        let context = EditorState.AutoCenterContext(
            content: contentImage,
            fill: fill,
            inset: 0,
            card: image,
            baseShift: .zero,
            appliedShift: .zero
        )
        state.autoCenter = context
        return context
    }

    private func setLiveInset(_ newInset: CGFloat) {
        guard let context = ensureInsetContext() else { return }
        if insetDragStart == nil {
            insetDragStart = (
                state.document.screenshot,
                state.document.baseSelection,
                state.document.padding,
                context.appliedShift,
                context
            )
        }
        let rect = CGRect(x: 0, y: 0, width: context.content.width, height: context.content.height)
        guard let card = ContentInsetComposer.compose(
            screenshot: context.content, content: rect, inset: newInset, fill: context.fill
        ) else { return }
        let targetShift = CGSize(width: context.baseShift.width + newInset, height: context.baseShift.height + newInset)
        let delta = CGSize(width: targetShift.width - context.appliedShift.width, height: targetShift.height - context.appliedShift.height)
        state.document.screenshot = card
        state.document.baseSelection = CGRect(x: 0, y: 0, width: card.width, height: card.height)
        translateAnnotations(by: delta)
        state.autoCenter?.inset = newInset
        state.autoCenter?.card = card
        state.autoCenter?.appliedShift = targetShift
    }

    private func commitInsetDrag() {
        guard let start = insetDragStart else { return }
        let toScreenshot = state.document.screenshot
        let toSelection = state.document.baseSelection
        let endShift = state.autoCenter?.appliedShift ?? start.shift
        let net = CGSize(width: endShift.width - start.shift.width, height: endShift.height - start.shift.height)
        // Rewind to the drag start, then record one undoable step covering the whole drag.
        state.document.screenshot = start.screenshot
        state.document.baseSelection = start.selection
        translateAnnotations(by: CGSize(width: -net.width, height: -net.height))
        if toScreenshot !== start.screenshot {
            state.performCommand(ApplyAutoCenterCommand(
                fromScreenshot: start.screenshot,
                toScreenshot: toScreenshot,
                fromSelection: start.selection,
                toSelection: toSelection,
                fromPadding: start.padding,
                toPadding: start.padding,
                annotationDelta: net,
                fromAutoCenter: start.context.bound(toCard: start.screenshot),
                toAutoCenter: state.autoCenter?.bound(toCard: toScreenshot)
            ))
        }
        insetDragStart = nil
    }

    private func translateAnnotations(by delta: CGSize) {
        guard delta != .zero else { return }
        for index in state.document.annotations.indices {
            state.document.annotations[index].kind = AnnotationGeometry.translated(
                state.document.annotations[index].kind, by: delta
            )
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
                InspectorValueLabel(text: "\(Int(state.document.cardCornerRadius ?? 0))", suffix: "px")
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
                InspectorValueLabel(text: "\(Int(screenshotCornerValue))", suffix: "px")
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
                shadowSlider("Blur", value: shadow.blur, range: 0...Double(ShadowConfig.maximumBlur), suffix: "px") {
                    var next = shadow; next.blur = $0; commitShadow(next)
                }
                shadowSlider(
                    "Offset X",
                    value: shadow.offsetX,
                    range: -Double(ShadowConfig.maximumOffset)...Double(ShadowConfig.maximumOffset),
                    suffix: "px"
                ) {
                    var next = shadow; next.offsetX = $0; commitShadow(next)
                }
                shadowSlider(
                    "Offset Y",
                    value: shadow.offsetY,
                    range: -Double(ShadowConfig.maximumOffset)...Double(ShadowConfig.maximumOffset),
                    suffix: "px"
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
        commit(padding.setting(side, to: value))
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

    private func applyAutoCenter() {
        guard !isCentering else { return }
        isCentering = true
        let image = state.document.screenshot
        let region = state.document.baseSelection
        let fromPadding = state.document.padding
        Task {
            let result = await Task.detached(priority: .userInitiated) { () -> (ApplyAutoCenterCommand, EditorState.AutoCenterContext)? in
                guard let content = ContentBoundsDetector().detect(in: image, region: region),
                      let contentImage = image.cropping(to: content.box.integral) else { return nil }
                let inset = Self.contentInset(forContentSize: content.box.size)
                guard let card = ContentInsetComposer.compose(
                    screenshot: image, content: content.box, inset: inset, fill: content.fillColor
                ) else { return nil }

                let toSelection = CGRect(x: 0, y: 0, width: card.width, height: card.height)
                let toPadding = Self.resolvedUniformPadding(fromPadding, cardSize: toSelection.size)
                // Glue annotations: shift by the content's new origin minus its old one.
                let delta = CGSize(
                    width: region.minX - content.box.minX + inset,
                    height: region.minY - content.box.minY + inset
                )
                let command = ApplyAutoCenterCommand(
                    fromScreenshot: image,
                    toScreenshot: card,
                    fromSelection: region,
                    toSelection: toSelection,
                    fromPadding: fromPadding,
                    toPadding: toPadding,
                    annotationDelta: delta
                )
                let baseShift = CGSize(width: region.minX - content.box.minX, height: region.minY - content.box.minY)
                let context = EditorState.AutoCenterContext(
                    content: contentImage, fill: content.fillColor, inset: inset, card: card,
                    baseShift: baseShift, appliedShift: delta
                )
                return (command, context)
            }.value

            isCentering = false
            guard let (command, context) = result,
                  state.document.screenshot === image,
                  state.document.baseSelection == region else { return }
            state.performCommand(command.withAutoCenterContexts(
                from: activeInsetContext,
                to: context.bound(toCard: command.toScreenshot)
            ))
        }
    }

    /// Equal outer margins: keep the user's uniform amount if they set one, else
    /// the size-derived sweet spot.
    nonisolated private static func resolvedUniformPadding(_ current: PaddingConfig, cardSize: CGSize) -> PaddingConfig {
        if let uniform = current.uniform, uniform > 0 {
            return current
        }
        return PaddingConfig.autoSweetSpot(forSelection: cardSize).clamped()
    }

    /// Synthesized whitespace band inside the card: ~6% of the content's longer
    /// side, clamped so small shots get room and large shots aren't drowned.
    nonisolated private static func contentInset(forContentSize size: CGSize) -> CGFloat {
        let maxSide = max(size.width, size.height)
        return min(max((0.06 * maxSide).rounded(), 24), 96)
    }

    private func commitDrag() {
        guard let from = editStart else { return }
        let to = padding
        state.document.padding = from
        state.performCommand(SetPaddingCommand(from: from, to: to.clamped()))
        editStart = nil
    }
}
