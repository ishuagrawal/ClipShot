import AppKit
import SwiftUI

/// Padding detail panel with per-side box-model controls.
struct PaddingToolView: View {
    @ObservedObject var state: EditorState
    @State private var editStart: PaddingConfig?
    @State private var shotCornerEditing: Bool = false
    @State private var shotCornerStart: CGFloat?
    @State private var shadowColor = Color(cgColor: ShadowConfig.default.color)
    @State private var syncingShadow = false
    @State private var isCentering = false
    @State private var centerCache: CenterCache?
    @State private var insetDragStart: (
        screenshot: CGImage,
        selection: CGRect,
        padding: PaddingConfig,
        shift: CGSize,
        context: EditorState.AutoCenterContext
    )?

    private let paddingRange: ClosedRange<Double> = 0...Double(PaddingConfig.maximum)

    private var screenshotCornerRange: ClosedRange<Double> {
        // Subtle ceiling — a gentle round, never a pill/ellipse.
        let halfSide = min(state.document.baseSelection.width, state.document.baseSelection.height) / 2
        let maximum = min(halfSide, 50)
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

    private var isCentered: Bool { activeInsetContext?.centered == true }

    private var header: some View {
        HStack {
            CenterToggle(isOn: isCentered) { toggleCenter() }
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
        // Cap to the base inner width and center, so the glyph stays a compact
        // diagram on wide panels instead of ballooning with the card.
        .frame(maxWidth: 240)
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

    // MARK: - Screenshot corners

    private var screenshotCornerRow: some View {
        PanelSection("Corner Radius") {
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
                InspectorValueLabel(text: "\(Int(screenshotCornerValue))", suffix: "px")
            }
        }
    }

    private var screenshotCornerValue: CGFloat {
        state.document.effectiveSelectionCornerRadii.uniformRadius ?? 0
    }

    private func setLiveShotCorner(_ value: CGFloat) {
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
            SetScreenshotCornerCommand(fromRadius: from, toRadius: to)
        )
        shotCornerEditing = false
        shotCornerStart = nil
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

    private func toggleCenter() {
        guard !isCentering else { return }
        if isCentered { disableCenter() } else { enableCenter() }
    }

    /// The expensive trim+compose of the pristine capture. The original never
    /// changes, so once computed the cache stays valid for the document's life.
    private struct CenterCache {
        let sourceScreenshot: CGImage
        let region: CGRect
        let contentBox: CGRect
        let contentImage: CGImage
        let fill: CGColor
        let inset: CGFloat
        let card: CGImage
        let baseShift: CGSize
    }

    /// Center always trims the original captured image and swaps only the
    /// screenshot, gluing annotations to the content shift. Padding, corner,
    /// background, and shadow are document properties and ride along untouched.
    private func enableCenter() {
        let original = state.originalDocument
        let image = original.screenshot
        let region = original.baseSelection

        if let cache = centerCache, cache.sourceScreenshot === image {
            applyCenter(from: cache)
            return
        }
        isCentering = true
        Task {
            let cache = await Task.detached(priority: .userInitiated) { () -> CenterCache? in
                guard let content = ContentBoundsDetector().detect(in: image, region: region),
                      let contentImage = image.cropping(to: content.box.integral) else { return nil }
                let inset = Self.contentInset(forContentSize: content.box.size)
                guard let card = ContentInsetComposer.compose(
                    screenshot: image, content: content.box, inset: inset, fill: content.fillColor
                ) else { return nil }
                let baseShift = CGSize(width: region.minX - content.box.minX, height: region.minY - content.box.minY)
                return CenterCache(
                    sourceScreenshot: image, region: region, contentBox: content.box,
                    contentImage: contentImage, fill: content.fillColor, inset: inset,
                    card: card, baseShift: baseShift
                )
            }.value

            isCentering = false
            guard let cache, !isCentered else { return }
            centerCache = cache
            applyCenter(from: cache)
        }
    }

    private func applyCenter(from cache: CenterCache) {
        let padding = state.document.padding
        let toSelection = CGRect(x: 0, y: 0, width: cache.card.width, height: cache.card.height)
        // Total annotation shift from the ORIGINAL content origin into the card.
        let delta = CGSize(
            width: cache.region.minX - cache.contentBox.minX + cache.inset,
            height: cache.region.minY - cache.contentBox.minY + cache.inset
        )
        // Annotations may already be displaced by an independent un-centered inset
        // band; the band is discarded by centering, so move only the remainder.
        let priorShift = activeInsetContext?.appliedShift ?? .zero
        let netDelta = CGSize(width: delta.width - priorShift.width, height: delta.height - priorShift.height)
        // Remember the view we're leaving so disabling Center returns to it.
        let origin = EditorState.CenterOrigin(
            screenshot: state.document.screenshot,
            selection: state.document.baseSelection,
            shift: priorShift,
            context: activeInsetContext
        )
        let context = EditorState.AutoCenterContext(
            content: cache.contentImage, fill: cache.fill, inset: cache.inset, card: cache.card,
            centered: true, origin: origin, baseShift: cache.baseShift, appliedShift: delta
        )
        state.performCommand(ApplyAutoCenterCommand(
            fromScreenshot: state.document.screenshot,
            toScreenshot: cache.card,
            fromSelection: state.document.baseSelection,
            toSelection: toSelection,
            fromPadding: padding,
            toPadding: padding,
            annotationDelta: netDelta,
            fromAutoCenter: activeInsetContext,
            toAutoCenter: context.bound(toCard: cache.card)
        ))
    }

    /// Return to the view that existed just before centering — including an
    /// un-centered inset band, if any. Padding, corner, and background ride along.
    private func disableCenter() {
        guard let context = activeInsetContext, let origin = context.origin else { return }
        let padding = state.document.padding
        // Annotations sit at the centered shift; move them back to the origin shift.
        let revertDelta = CGSize(
            width: origin.shift.width - context.appliedShift.width,
            height: origin.shift.height - context.appliedShift.height
        )
        state.performCommand(ApplyAutoCenterCommand(
            fromScreenshot: state.document.screenshot,
            toScreenshot: origin.screenshot,
            fromSelection: state.document.baseSelection,
            toSelection: origin.selection,
            fromPadding: padding,
            toPadding: padding,
            annotationDelta: revertDelta,
            fromAutoCenter: context,
            toAutoCenter: origin.context
        ))
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

/// The Center action as a stateful toggle. Off reads as an inviting accent
/// control (tinted fill, accent hairline); on recesses into a glowing accent
/// slab so the engaged state never looks like a plain button.
private struct CenterToggle: View {
    let isOn: Bool
    let action: () -> Void
    @State private var hovering = false

    private static let shape = RoundedRectangle(cornerRadius: 8, style: .continuous)

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: "arrow.down.right.and.arrow.up.left")
                    .font(.system(size: 11, weight: .semibold))
                Text("Center").font(.system(size: 11.5, weight: .semibold))
            }
            .foregroundStyle(isOn ? Theme.accentInk : Theme.textPrimary)
            .padding(.horizontal, 11)
            .frame(height: 28)
            .background(background)
            .overlay(Self.shape.stroke(strokeColor, lineWidth: 1))
            .contentShape(Self.shape)
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.14), value: isOn)
        .animation(.easeOut(duration: 0.12), value: hovering)
        .help(isOn ? "Revert to the original framing" : "Trim to content and center with equal inset")
        .accessibilityAddTraits(isOn ? [.isSelected] : [])
    }

    @ViewBuilder private var background: some View {
        if isOn {
            // Engaged: recessed accent slab — inner shadow reads as "pressed in".
            Self.shape.fill(
                LinearGradient(colors: [Theme.accent, Theme.accentText], startPoint: .top, endPoint: .bottom)
                    .shadow(.inner(color: .black.opacity(0.38), radius: 3, y: 1))
            )
        } else {
            // Resting: visible accent wash so the feature invites a click.
            Self.shape.fill(Theme.accent.opacity(hovering ? 0.24 : 0.15))
        }
    }

    private var strokeColor: Color {
        isOn ? Color.black.opacity(0.25)
            : Theme.accentFocus.opacity(hovering ? 1.0 : 0.7)
    }
}
