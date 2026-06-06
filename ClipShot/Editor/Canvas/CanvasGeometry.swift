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

    static func annotationPoint(
        fromCanvasPoint point: CGPoint,
        canvasOriginInImage: CGPoint,
        baseSelection: CGRect
    ) -> CGPoint {
        annotationPoint(
            fromImagePixel: CGPoint(
                x: point.x + canvasOriginInImage.x,
                y: point.y + canvasOriginInImage.y
            ),
            baseSelection: baseSelection
        )
    }

    static func canvasPoint(
        fromAnnotationPoint point: CGPoint,
        canvasOriginInImage: CGPoint,
        baseSelection: CGRect
    ) -> CGPoint {
        let imagePoint = imagePixel(fromAnnotationPoint: point, baseSelection: baseSelection)
        return CGPoint(
            x: imagePoint.x - canvasOriginInImage.x,
            y: imagePoint.y - canvasOriginInImage.y
        )
    }
}
