import CoreGraphics

/// Converts between screenshot image pixels and annotation coordinates.
/// Annotation coordinates are anchored to `baseSelection` and never change
/// when padding changes.
enum CanvasGeometry {
    static func annotationPoint(fromImagePixel point: CGPoint, baseSelection: CGRect) -> CGPoint {
        CGPoint(x: point.x - baseSelection.minX, y: point.y - baseSelection.minY)
    }

    static func imagePixel(fromAnnotationPoint point: CGPoint, baseSelection: CGRect) -> CGPoint {
        CGPoint(x: point.x + baseSelection.minX, y: point.y + baseSelection.minY)
    }
}
