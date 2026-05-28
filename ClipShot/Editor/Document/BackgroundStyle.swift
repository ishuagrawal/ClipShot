import CoreGraphics

enum BackgroundStyle: Equatable {
    case none
    case solidColor(CGColor)
    case gradient(start: CGColor, end: CGColor, angleDegrees: CGFloat)
    case blurExtend(radius: CGFloat)
}
