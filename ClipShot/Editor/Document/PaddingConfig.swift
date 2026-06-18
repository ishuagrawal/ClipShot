import CoreGraphics

struct PaddingConfig: Equatable {
    var top: CGFloat
    var right: CGFloat
    var bottom: CGFloat
    var left: CGFloat

    static let zero = PaddingConfig(top: 0, right: 0, bottom: 0, left: 0)

    /// Returns the common value when all four sides are equal, otherwise nil.
    var uniform: CGFloat? {
        guard top == right, right == bottom, bottom == left else { return nil }
        return top
    }
}

enum PaddingSide: CaseIterable {
    case top
    case right
    case bottom
    case left
}

extension PaddingConfig {
    static let maximum: CGFloat = 200

    static func uniform(_ value: CGFloat) -> PaddingConfig {
        PaddingConfig(top: value, right: value, bottom: value, left: value)
    }

    /// Visually-balanced uniform padding derived from the screenshot size:
    /// ~6% of the longer side, clamped so small shots aren't starved and huge
    /// shots aren't drowned.
    static func autoSweetSpot(forSelection size: CGSize) -> PaddingConfig {
        let maxSide = max(size.width, size.height)
        let raw = (0.06 * maxSide).rounded()
        let pad = min(max(raw, 40), 200)
        return .uniform(pad)
    }

    var isZero: Bool { self == .zero }

    func setting(_ side: PaddingSide, to value: CGFloat) -> PaddingConfig {
        var copy = self
        switch side {
        case .top:
            copy.top = value
        case .right:
            copy.right = value
        case .bottom:
            copy.bottom = value
        case .left:
            copy.left = value
        }
        return copy
    }

    func clamped(to range: ClosedRange<CGFloat> = 0...PaddingConfig.maximum) -> PaddingConfig {
        func clamp(_ value: CGFloat) -> CGFloat {
            min(max(value, range.lowerBound), range.upperBound)
        }
        return PaddingConfig(
            top: clamp(top),
            right: clamp(right),
            bottom: clamp(bottom),
            left: clamp(left)
        )
    }
}
