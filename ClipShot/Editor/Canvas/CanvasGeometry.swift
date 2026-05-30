import CoreGraphics

/// Pure conversions between document points (origin at effectiveCrop top-left,
/// y-down, 1 unit = 1 image pixel) and screenshot image pixels.
enum CanvasGeometry {
    static func documentPoint(fromImagePixel point: CGPoint, effectiveCrop: CGRect) -> CGPoint {
        CGPoint(x: point.x - effectiveCrop.minX, y: point.y - effectiveCrop.minY)
    }

    static func imagePixel(fromDocumentPoint point: CGPoint, effectiveCrop: CGRect) -> CGPoint {
        CGPoint(x: point.x + effectiveCrop.minX, y: point.y + effectiveCrop.minY)
    }
}
