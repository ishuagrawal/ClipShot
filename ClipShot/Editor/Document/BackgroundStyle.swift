import CoreGraphics

enum BackgroundStyle: Equatable {
    case none
    case solidColor(CGColor)
    case gradient(start: CGColor, end: CGColor, angleDegrees: CGFloat)
    case dynamic
}

extension BackgroundStyle {
    /// Discrete style identity for the sidebar tile selection.
    enum Kind: CaseIterable, Hashable {
        case none
        case solid
        case gradient
        case dynamic
    }

    var kind: Kind {
        switch self {
        case .none:
            return .none
        case .solidColor:
            return .solid
        case .gradient:
            return .gradient
        case .dynamic:
            return .dynamic
        }
    }
}

extension BackgroundStyle {
    /// Single source of truth for the default blue gradient used by auto-padding
    /// (on-capture seed + Auto button) and the background panel's initial state.
    static let defaultGradientStart = CGColor(srgbRed: 0.12, green: 0.36, blue: 0.72, alpha: 1)
    static let defaultGradientEnd = CGColor(srgbRed: 0.20, green: 0.65, blue: 0.85, alpha: 1)
    static let defaultGradientAngle: CGFloat = 135

    static let defaultGradient = BackgroundStyle.gradient(
        start: defaultGradientStart,
        end: defaultGradientEnd,
        angleDegrees: defaultGradientAngle
    )
}
