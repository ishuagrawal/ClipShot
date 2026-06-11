import CoreGraphics
import Foundation

struct SelectionCornerRadii: Equatable {
    var topLeft: CGSize
    var topRight: CGSize
    var bottomRight: CGSize
    var bottomLeft: CGSize

    static let zero = SelectionCornerRadii(
        topLeft: .zero,
        topRight: .zero,
        bottomRight: .zero,
        bottomLeft: .zero
    )

    static func uniform(_ radius: CGFloat) -> SelectionCornerRadii {
        let size = CGSize(width: radius, height: radius)
        return SelectionCornerRadii(
            topLeft: size,
            topRight: size,
            bottomRight: size,
            bottomLeft: size
        )
    }

    /// Radii for a rounded rect offset outward by `padding`. Offsetting a rounded
    /// corner outward by distance d grows its radius by d, so each corner grows by
    /// the two adjacent paddings. Square (zero) corners stay square.
    func concentricOuter(padding: PaddingConfig) -> SelectionCornerRadii {
        guard !isZero else { return .zero }
        func grow(_ corner: CGSize, dx: CGFloat, dy: CGFloat) -> CGSize {
            guard corner.width > 0 || corner.height > 0 else { return .zero }
            return CGSize(width: corner.width + dx, height: corner.height + dy)
        }
        return SelectionCornerRadii(
            topLeft: grow(topLeft, dx: padding.left, dy: padding.top),
            topRight: grow(topRight, dx: padding.right, dy: padding.top),
            bottomRight: grow(bottomRight, dx: padding.right, dy: padding.bottom),
            bottomLeft: grow(bottomLeft, dx: padding.left, dy: padding.bottom)
        )
    }

    var isZero: Bool {
        [topLeft, topRight, bottomRight, bottomLeft].allSatisfy { radius in
            radius.width <= 0 && radius.height <= 0
        }
    }

    /// The single radius when all four corners are equal and circular (width == height); nil otherwise.
    var uniformRadius: CGFloat? {
        guard topLeft == topRight, topRight == bottomRight, bottomRight == bottomLeft,
              topLeft.width == topLeft.height else { return nil }
        return topLeft.width > 0 ? topLeft.width : nil
    }

    func clamped(to size: CGSize) -> SelectionCornerRadii {
        let width = max(0, size.width)
        let height = max(0, size.height)

        let normalized = SelectionCornerRadii(
            topLeft: topLeft.nonNegative,
            topRight: topRight.nonNegative,
            bottomRight: bottomRight.nonNegative,
            bottomLeft: bottomLeft.nonNegative
        )

        let sideRatios = [
            width / max(1, normalized.topLeft.width + normalized.topRight.width),
            width / max(1, normalized.bottomLeft.width + normalized.bottomRight.width),
            height / max(1, normalized.topLeft.height + normalized.bottomLeft.height),
            height / max(1, normalized.topRight.height + normalized.bottomRight.height)
        ]
        let scale = min(1, sideRatios.min() ?? 1)

        return SelectionCornerRadii(
            topLeft: normalized.topLeft.scaled(by: scale),
            topRight: normalized.topRight.scaled(by: scale),
            bottomRight: normalized.bottomRight.scaled(by: scale),
            bottomLeft: normalized.bottomLeft.scaled(by: scale)
        )
    }

    func path(in rect: CGRect) -> CGPath {
        clamped(to: rect.size).makePath(in: rect)
    }

    private func makePath(in rect: CGRect) -> CGPath {
        let k: CGFloat = 0.552_284_749_830_793_6
        let path = CGMutablePath()

        path.move(to: CGPoint(x: rect.minX + topLeft.width, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX - topRight.width, y: rect.minY))
        addCorner(
            to: path,
            end: CGPoint(x: rect.maxX, y: rect.minY + topRight.height),
            cp1: CGPoint(x: rect.maxX - topRight.width + topRight.width * k, y: rect.minY),
            cp2: CGPoint(x: rect.maxX, y: rect.minY + topRight.height - topRight.height * k),
            radius: topRight
        )

        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - bottomRight.height))
        addCorner(
            to: path,
            end: CGPoint(x: rect.maxX - bottomRight.width, y: rect.maxY),
            cp1: CGPoint(x: rect.maxX, y: rect.maxY - bottomRight.height + bottomRight.height * k),
            cp2: CGPoint(x: rect.maxX - bottomRight.width + bottomRight.width * k, y: rect.maxY),
            radius: bottomRight
        )

        path.addLine(to: CGPoint(x: rect.minX + bottomLeft.width, y: rect.maxY))
        addCorner(
            to: path,
            end: CGPoint(x: rect.minX, y: rect.maxY - bottomLeft.height),
            cp1: CGPoint(x: rect.minX + bottomLeft.width - bottomLeft.width * k, y: rect.maxY),
            cp2: CGPoint(x: rect.minX, y: rect.maxY - bottomLeft.height + bottomLeft.height * k),
            radius: bottomLeft
        )

        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY + topLeft.height))
        addCorner(
            to: path,
            end: CGPoint(x: rect.minX + topLeft.width, y: rect.minY),
            cp1: CGPoint(x: rect.minX, y: rect.minY + topLeft.height - topLeft.height * k),
            cp2: CGPoint(x: rect.minX + topLeft.width - topLeft.width * k, y: rect.minY),
            radius: topLeft
        )

        path.closeSubpath()
        return path
    }

    private func addCorner(
        to path: CGMutablePath,
        end: CGPoint,
        cp1: CGPoint,
        cp2: CGPoint,
        radius: CGSize
    ) {
        if radius.width <= 0 || radius.height <= 0 {
            path.addLine(to: end)
        } else {
            path.addCurve(to: end, control1: cp1, control2: cp2)
        }
    }
}

private extension CGSize {
    var nonNegative: CGSize {
        CGSize(width: max(0, width), height: max(0, height))
    }

    func scaled(by scale: CGFloat) -> CGSize {
        CGSize(width: width * scale, height: height * scale)
    }
}

/// Tunable drop shadow cast by the screenshot card onto the background. Only
/// rendered when there is padding (otherwise the card fills the crop, no room).
/// Offsets are in image px, screen-oriented: +x right, +y down. Each renderer
/// converts the y sign for its own coordinate space.
struct ShadowConfig: Equatable {
    static let maximumBlur: CGFloat = 44
    static let maximumOffset: CGFloat = 32
    static let maximumOpacity: CGFloat = 0.80

    var isEnabled: Bool
    var blur: CGFloat        // radius, px
    var offsetX: CGFloat     // px, + = right
    var offsetY: CGFloat     // px, + = down (screen)
    var opacity: CGFloat     // 0…1
    var color: CGColor       // hue only; `opacity` applied separately

    static let `default` = ShadowConfig(
        isEnabled: true,
        blur: 30,
        offsetX: 0,
        offsetY: 8,
        opacity: 0.30,
        color: CGColor(srgbRed: 0, green: 0, blue: 0, alpha: 1)
    )

    var clamped: ShadowConfig {
        var copy = self
        copy.blur = min(max(0, blur), Self.maximumBlur)
        copy.offsetX = min(max(-Self.maximumOffset, offsetX), Self.maximumOffset)
        copy.offsetY = min(max(-Self.maximumOffset, offsetY), Self.maximumOffset)
        copy.opacity = min(max(0, opacity), Self.maximumOpacity)
        return copy
    }
}

/// Post-effects layered on top of any non-empty background style.
struct BackgroundEffects: Equatable {
    static let maximumBlurRadius: CGFloat = 24
    static let maximumNoiseOpacity: CGFloat = 0.20

    var blurRadius: CGFloat    // gaussian sigma, px; 0 = off
    var noiseOpacity: CGFloat  // 0…1 grain opacity; 0 = off

    static let none = BackgroundEffects(blurRadius: 0, noiseOpacity: 0)

    var isActive: Bool { blurRadius > 0 || noiseOpacity > 0 }

    var clamped: BackgroundEffects {
        BackgroundEffects(
            blurRadius: min(max(0, blurRadius), Self.maximumBlurRadius),
            noiseOpacity: min(max(0, noiseOpacity), Self.maximumNoiseOpacity)
        )
    }
}

struct EditorDocument {
    let screenshot: CGImage
    let viewport: CGSize            // CSS px, informational only — rendering uses baseSelection (imagePx)
    var pageTitle: String           // user-editable in the top bar; drives the export filename
    let pageURL: String

    let baseSelection: CGRect       // imagePx coords, clamped to ≥ 8×8 on init
    let selectionCornerRadii: SelectionCornerRadii
    // The screenshot's VISUAL corner radius, separate from selectionCornerRadii (the
    // mask we APPLY to a rectangular shot). Native window shots bake their rounded
    // corners into the pixels and leave selectionCornerRadii zero, but carry the
    // measured radius here so concentric outer rounding still matches. Defaults to
    // selectionCornerRadii for DOM/web captures. Drives ONLY outerCornerRadii.
    let contentCornerRadii: SelectionCornerRadii
    // Mutations bump version unconditionally (even no-op writes) so the canvas can
    // treat version as a cheap change token without value-diffing.
    var padding: PaddingConfig      { didSet { bumpVersion() } }
    var background: BackgroundStyle { didSet { bumpVersion() } }
    var annotations: [Annotation]   { didSet { bumpVersion() } }
    // User-set uniform card corner radius. nil = auto (concentric, derived from
    // the screenshot's own radius + padding). 0 = explicitly square.
    var cardCornerOverride: CGFloat? { didSet { bumpVersion() } }
    var shadow: ShadowConfig { didSet { bumpVersion() } }
    var backgroundEffects: BackgroundEffects { didSet { bumpVersion() } }
    // The screenshot's OWN uniform corner radius, user-set. nil = use the captured
    // selectionCornerRadii. Also feeds concentric card derivation (effectiveContentCornerRadii).
    var screenshotCornerOverride: CGFloat? { didSet { bumpVersion() } }
    // When true, the screenshot's drawn corners mirror the card radius (inner == outer),
    // overriding screenshotCornerOverride for display.
    var lockCornersToCard: Bool { didSet { bumpVersion() } }
    private(set) var version: Int

    init(
        screenshot: CGImage,
        viewport: CGSize,
        pageTitle: String,
        pageURL: String,
        baseSelection: CGRect,
        selectionCornerRadii: SelectionCornerRadii = .zero,
        contentCornerRadii: SelectionCornerRadii? = nil,
        padding: PaddingConfig = .zero,
        background: BackgroundStyle = .none,
        annotations: [Annotation] = [],
        cardCornerOverride: CGFloat? = nil,
        shadow: ShadowConfig = .default,
        backgroundEffects: BackgroundEffects = .none,
        screenshotCornerOverride: CGFloat? = nil,
        lockCornersToCard: Bool = false
    ) {
        self.screenshot = screenshot
        self.viewport = viewport
        self.pageTitle = pageTitle
        self.pageURL = pageURL
        let minSide: CGFloat = 8
        self.baseSelection = CGRect(
            x: baseSelection.origin.x,
            y: baseSelection.origin.y,
            width: max(minSide, baseSelection.width),
            height: max(minSide, baseSelection.height)
        )
        self.selectionCornerRadii = selectionCornerRadii.clamped(to: self.baseSelection.size)
        self.contentCornerRadii = (contentCornerRadii ?? selectionCornerRadii).clamped(to: self.baseSelection.size)
        self.padding = padding
        self.background = background
        self.annotations = annotations
        self.cardCornerOverride = cardCornerOverride
        self.shadow = shadow
        self.backgroundEffects = backgroundEffects
        self.screenshotCornerOverride = screenshotCornerOverride
        self.lockCornersToCard = lockCornersToCard
        self.version = 0
    }

    private mutating func bumpVersion() { version &+= 1 }

    var effectiveCrop: CGRect {
        CGRect(
            x: baseSelection.minX - padding.left,
            y: baseSelection.minY - padding.top,
            width: baseSelection.width + padding.left + padding.right,
            height: baseSelection.height + padding.top + padding.bottom
        )
    }

    /// Content radii used to derive the concentric card. Reflects the user's
    /// screenshot-radius override when present, else the captured content radii.
    var effectiveContentCornerRadii: SelectionCornerRadii {
        if let override = screenshotCornerOverride {
            return SelectionCornerRadii.uniform(max(0, override)).clamped(to: baseSelection.size)
        }
        return contentCornerRadii
    }

    /// The screenshot's drawn corner radii. Locked → mirror the card radius
    /// (inner == outer); else the user override; else the captured mask.
    var effectiveSelectionCornerRadii: SelectionCornerRadii {
        if lockCornersToCard, let card = cardCornerRadius {
            return SelectionCornerRadii.uniform(card).clamped(to: baseSelection.size)
        }
        if let override = screenshotCornerOverride {
            return SelectionCornerRadii.uniform(max(0, override)).clamped(to: baseSelection.size)
        }
        return selectionCornerRadii
    }

    /// The true outward offset of the screenshot corners. This remains available
    /// while a manual card override is active so "Concentric" can restore it.
    var concentricOuterCornerRadii: SelectionCornerRadii {
        let content = effectiveContentCornerRadii
        guard !content.isZero, !padding.isZero else { return .zero }
        return content
            .concentricOuter(padding: padding)
            .clamped(to: effectiveCrop.size)
    }

    /// Concentric outer corner radii for the padded card. Zero when a manual card
    /// override is active because that override is rendered as a uniform radius.
    var outerCornerRadii: SelectionCornerRadii {
        guard cardCornerOverride == nil else { return .zero }
        return concentricOuterCornerRadii
    }

    /// Uniform card radius when either a manual override is set or the true
    /// concentric outer radii are uniform. Non-uniform concentric corners fall
    /// back to the per-corner `outerCornerRadii` path.
    var cardCornerRadius: CGFloat? {
        if let override = cardCornerOverride {
            return min(max(0, override), maxCardCornerRadius)
        }
        return autoCardCornerRadius
    }

    /// Largest legal card radius for the current padded card.
    var maxCardCornerRadius: CGFloat {
        min(effectiveCrop.width, effectiveCrop.height) / 2
    }

    /// The radius the card uses in auto mode, matching the screenshot's effective
    /// uniform radius exactly. nil when there is no padding or uniform radius.
    var autoCardCornerRadius: CGFloat? {
        guard !padding.isZero, let r = effectiveContentCornerRadii.uniformRadius else { return nil }
        return min(r, maxCardCornerRadius)
    }

    /// Whether the currently rendered inner and outer components use the same
    /// uniform radius. A small tolerance absorbs slider and pixel rounding.
    var isCardCornerConcentric: Bool {
        guard !padding.isZero, let outer = cardCornerRadius else { return false }
        let innerRadii = lockCornersToCard ? effectiveSelectionCornerRadii : effectiveContentCornerRadii
        guard let inner = innerRadii.uniformRadius else { return false }
        return abs(inner - outer) <= 0.5
    }

    var imageBounds: CGRect {
        CGRect(x: 0, y: 0, width: CGFloat(screenshot.width), height: CGFloat(screenshot.height))
    }

    var paddedDocumentSize: CGSize { effectiveCrop.size }

    /// The rect canvas fits frame. With a background the padded card is the
    /// visual artifact; with none the padding is invisible, so the screenshot
    /// itself fills the screen instead.
    var fitFocusRect: CGRect {
        background.kind == .none ? baseSelection : effectiveCrop
    }

    /// Legal annotation coordinates, anchored at the screenshot selection.
    /// Padding extends these bounds outward without moving existing annotations.
    var annotationBounds: CGRect {
        CGRect(
            x: -padding.left,
            y: -padding.top,
            width: paddedDocumentSize.width,
            height: paddedDocumentSize.height
        )
    }
}

// Equal only when ALL fields AND `version` match (screenshot compared by identity).
// This means two independently-built documents with identical content are NOT equal
// unless their version counters also match — use `==` to detect a specific snapshot,
// not for content equivalence.
extension EditorDocument: Equatable {
    static func == (lhs: EditorDocument, rhs: EditorDocument) -> Bool {
        lhs.screenshot === rhs.screenshot
        && lhs.viewport == rhs.viewport
        && lhs.pageTitle == rhs.pageTitle
        && lhs.pageURL == rhs.pageURL
        && lhs.baseSelection == rhs.baseSelection
        && lhs.selectionCornerRadii == rhs.selectionCornerRadii
        && lhs.contentCornerRadii == rhs.contentCornerRadii
        && lhs.padding == rhs.padding
        && lhs.background == rhs.background
        && lhs.annotations == rhs.annotations
        && lhs.cardCornerOverride == rhs.cardCornerOverride
        && lhs.shadow == rhs.shadow
        && lhs.backgroundEffects == rhs.backgroundEffects
        && lhs.screenshotCornerOverride == rhs.screenshotCornerOverride
        && lhs.lockCornersToCard == rhs.lockCornersToCard
        && lhs.version == rhs.version
    }
}
