import CoreGraphics

enum BackgroundStyle: Equatable {
    case none
    case solidColor(CGColor)
    case gradient(start: CGColor, end: CGColor, angleDegrees: CGFloat)
    case blurExtend(radius: CGFloat)
}

extension BackgroundStyle {
    /// Discrete style identity for the sidebar tile selection.
    enum Kind: CaseIterable, Hashable {
        case none
        case solid
        case gradient
        case blurExtend
    }

    var kind: Kind {
        switch self {
        case .none:
            return .none
        case .solidColor:
            return .solid
        case .gradient:
            return .gradient
        case .blurExtend:
            return .blurExtend
        }
    }
}
