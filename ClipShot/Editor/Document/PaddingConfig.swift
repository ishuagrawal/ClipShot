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
