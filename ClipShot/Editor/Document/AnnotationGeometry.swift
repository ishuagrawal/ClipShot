import CoreGraphics
import CoreText
import Foundation

/// Pure geometry shared by export rendering and the canvas preview. All values
/// are selection-relative annotation coordinates: top-left origin, y-down,
/// one point per image pixel, with (0, 0) at `EditorDocument.baseSelection`.
enum AnnotationGeometry {

    static func arrowHeadLength(weight: CGFloat) -> CGFloat {
        max(10, weight * 3.5)
    }

    static func arrowLinePath(from: CGPoint, to: CGPoint, weight: CGFloat) -> CGPath {
        let head = arrowHeadLength(weight: weight)
        let dx = to.x - from.x
        let dy = to.y - from.y
        let length = max(hypot(dx, dy), 0.0001)
        let unit = CGPoint(x: dx / length, y: dy / length)
        let base = CGPoint(x: to.x - unit.x * head, y: to.y - unit.y * head)

        let path = CGMutablePath()
        path.move(to: from)
        path.addLine(to: length > head ? base : to)
        return path
    }

    static func arrowHeadPath(from: CGPoint, to: CGPoint, weight: CGFloat) -> CGPath {
        let head = arrowHeadLength(weight: weight)
        let dx = to.x - from.x
        let dy = to.y - from.y
        let length = max(hypot(dx, dy), 0.0001)
        let unit = CGPoint(x: dx / length, y: dy / length)
        let base = CGPoint(x: to.x - unit.x * head, y: to.y - unit.y * head)
        let halfWidth = head * 0.55
        let perpendicular = CGPoint(x: -unit.y, y: unit.x)
        let left = CGPoint(x: base.x + perpendicular.x * halfWidth, y: base.y + perpendicular.y * halfWidth)
        let right = CGPoint(x: base.x - perpendicular.x * halfWidth, y: base.y - perpendicular.y * halfWidth)

        let path = CGMutablePath()
        path.move(to: to)
        path.addLine(to: left)
        path.addLine(to: right)
        path.closeSubpath()
        return path
    }

    static func linePath(from: CGPoint, to: CGPoint) -> CGPath {
        let path = CGMutablePath()
        path.move(to: from)
        path.addLine(to: to)
        return path
    }

    /// Stroke dash pattern + line cap for a `LineDash` at a given weight. Dotted
    /// uses a near-zero dash with a round cap so each dab renders as a circle.
    static func dashStyle(_ dash: Annotation.LineDash, weight: CGFloat) -> (pattern: [CGFloat]?, cap: CGLineCap) {
        switch dash {
        case .solid:  return (nil, .butt)
        case .dashed: return ([weight * 3, weight * 2], .butt)
        case .dotted: return ([weight * 0.01, weight * 2], .round)
        }
    }

    static func rectPath(frame: CGRect, cornerRadius: CGFloat) -> CGPath {
        let rect = frame.standardized
        let radius = max(0, min(cornerRadius, min(rect.width, rect.height) / 2))
        return CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)
    }

    static func attributedText(_ string: String, fontSize: CGFloat, color: CGColor) -> NSAttributedString {
        let font = CTFontCreateWithName("Helvetica" as CFString, fontSize, nil)
        return NSAttributedString(
            string: string,
            attributes: [
                kCTFontAttributeName as NSAttributedString.Key: font,
                kCTForegroundColorAttributeName as NSAttributedString.Key: color
            ]
        )
    }

    static func textFrame(origin: CGPoint, string: String, fontSize: CGFloat) -> CGRect {
        let measured = string.isEmpty ? " " : string
        let line = CTLineCreateWithAttributedString(
            attributedText(measured, fontSize: fontSize, color: CGColor(gray: 0, alpha: 1))
        )
        let width = CTLineGetTypographicBounds(line, nil, nil, nil)
        let height = fontSize * 1.32
        return CGRect(x: origin.x, y: origin.y, width: ceil(CGFloat(width)), height: ceil(height))
    }

    static func boundingBox(_ kind: Annotation.Kind) -> CGRect {
        switch kind {
        case .arrow(let from, let to, _, let weight):
            let line = CGRect(
                x: min(from.x, to.x),
                y: min(from.y, to.y),
                width: abs(to.x - from.x),
                height: abs(to.y - from.y)
            )
            let pad = arrowHeadLength(weight: weight) * 0.6 + weight
            return line.insetBy(dx: -pad, dy: -pad)
        case .line(let from, let to, _, let weight, _):
            let line = CGRect(
                x: min(from.x, to.x),
                y: min(from.y, to.y),
                width: abs(to.x - from.x),
                height: abs(to.y - from.y)
            )
            return line.insetBy(dx: -weight, dy: -weight)
        case .rect(let frame, _, _, let weight, _):
            return frame.standardized.insetBy(dx: -weight, dy: -weight)
        case .text(let origin, let string, let fontSize, _):
            return textFrame(origin: origin, string: string, fontSize: fontSize)
        case .blur(let frame, _):
            return frame.standardized
        }
    }

    static func hitTest(_ kind: Annotation.Kind, point: CGPoint, tolerance: CGFloat) -> Bool {
        switch kind {
        case .arrow(let from, let to, _, let weight):
            return distance(point, segmentStart: from, segmentEnd: to) <= tolerance + weight / 2
        case .line(let from, let to, _, let weight, _):
            return distance(point, segmentStart: from, segmentEnd: to) <= tolerance + weight / 2
        case .rect(let frame, _, _, let weight, _):
            return frame.standardized
                .insetBy(dx: -(tolerance + weight), dy: -(tolerance + weight))
                .contains(point)
        case .text(let origin, let string, let fontSize, _):
            return textFrame(origin: origin, string: string, fontSize: fontSize)
                .insetBy(dx: -tolerance, dy: -tolerance)
                .contains(point)
        case .blur(let frame, _):
            return frame.standardized.insetBy(dx: -tolerance, dy: -tolerance).contains(point)
        }
    }

    static func translated(_ kind: Annotation.Kind, by delta: CGSize) -> Annotation.Kind {
        switch kind {
        case .arrow(let from, let to, let color, let weight):
            return .arrow(from: from.offset(delta), to: to.offset(delta), color: color, weight: weight)
        case .line(let from, let to, let color, let weight, let dash):
            return .line(from: from.offset(delta), to: to.offset(delta), color: color, weight: weight, dash: dash)
        case .rect(let frame, let stroke, let fill, let weight, let corner):
            return .rect(
                frame: frame.offsetBy(dx: delta.width, dy: delta.height),
                stroke: stroke,
                fill: fill,
                weight: weight,
                cornerRadius: corner
            )
        case .text(let origin, let string, let fontSize, let color):
            return .text(origin: origin.offset(delta), string: string, fontSize: fontSize, color: color)
        case .blur(let frame, let radius):
            return .blur(frame: frame.offsetBy(dx: delta.width, dy: delta.height), radius: radius)
        }
    }

    /// Translate `kind` by `delta`, clamping the delta so the annotation's
    /// bounding box stays within `bounds` WITHOUT resizing the annotation.
    /// Axes on which the shape is larger than `bounds` are left unclamped, so an
    /// oversized annotation simply moves freely rather than being squished.
    /// Tight bounds of the annotation's defining geometry (endpoints / frame /
    /// text box) — no stroke or arrowhead padding. Used for translation clamping
    /// so a shape already touching the border isn't nudged on an orthogonal axis.
    static func geometryExtent(_ kind: Annotation.Kind) -> CGRect {
        switch kind {
        case .arrow(let from, let to, _, _), .line(let from, let to, _, _, _):
            return CGRect(
                x: min(from.x, to.x),
                y: min(from.y, to.y),
                width: abs(to.x - from.x),
                height: abs(to.y - from.y)
            )
        case .rect(let frame, _, _, _, _):
            return frame.standardized
        case .text(let origin, let string, let fontSize, _):
            return textFrame(origin: origin, string: string, fontSize: fontSize)
        case .blur(let frame, _):
            return frame.standardized
        }
    }

    static func translatedClamped(_ kind: Annotation.Kind, by delta: CGSize, to bounds: CGRect) -> Annotation.Kind {
        let moved = geometryExtent(kind).offsetBy(dx: delta.width, dy: delta.height)
        var dx = delta.width
        var dy = delta.height

        if moved.width <= bounds.width {
            if moved.minX < bounds.minX {
                dx += bounds.minX - moved.minX
            } else if moved.maxX > bounds.maxX {
                dx -= moved.maxX - bounds.maxX
            }
        }
        if moved.height <= bounds.height {
            if moved.minY < bounds.minY {
                dy += bounds.minY - moved.minY
            } else if moved.maxY > bounds.maxY {
                dy -= moved.maxY - bounds.maxY
            }
        }

        return translated(kind, by: CGSize(width: dx, height: dy))
    }

    static func clamped(_ kind: Annotation.Kind, to bounds: CGRect) -> Annotation.Kind {
        switch kind {
        case .arrow(let from, let to, let color, let weight):
            return .arrow(from: from.clamped(to: bounds), to: to.clamped(to: bounds), color: color, weight: weight)
        case .line(let from, let to, let color, let weight, let dash):
            return .line(from: from.clamped(to: bounds), to: to.clamped(to: bounds), color: color, weight: weight, dash: dash)
        case .rect(let frame, let stroke, let fill, let weight, let corner):
            return .rect(
                frame: frame.standardized.clamped(to: bounds),
                stroke: stroke,
                fill: fill,
                weight: weight,
                cornerRadius: corner
            )
        case .text(let origin, let string, let fontSize, let color):
            let frame = textFrame(origin: origin, string: string, fontSize: fontSize).clamped(to: bounds)
            return .text(origin: frame.origin, string: string, fontSize: fontSize, color: color)
        case .blur(let frame, let radius):
            return .blur(frame: frame.standardized.clamped(to: bounds), radius: radius)
        }
    }

    static func distance(_ point: CGPoint, segmentStart start: CGPoint, segmentEnd end: CGPoint) -> CGFloat {
        let dx = end.x - start.x
        let dy = end.y - start.y
        let lengthSquared = dx * dx + dy * dy
        if lengthSquared < 0.0001 {
            return hypot(point.x - start.x, point.y - start.y)
        }

        let rawT = ((point.x - start.x) * dx + (point.y - start.y) * dy) / lengthSquared
        let t = min(max(rawT, 0), 1)
        let projection = CGPoint(x: start.x + t * dx, y: start.y + t * dy)
        return hypot(point.x - projection.x, point.y - projection.y)
    }
}

private extension CGPoint {
    func offset(_ delta: CGSize) -> CGPoint {
        CGPoint(x: x + delta.width, y: y + delta.height)
    }

    func clamped(to rect: CGRect) -> CGPoint {
        CGPoint(
            x: min(max(x, rect.minX), rect.maxX),
            y: min(max(y, rect.minY), rect.maxY)
        )
    }
}

private extension CGRect {
    func clamped(to bounds: CGRect) -> CGRect {
        let width = min(self.width, bounds.width)
        let height = min(self.height, bounds.height)
        let x = min(max(minX, bounds.minX), bounds.maxX - width)
        let y = min(max(minY, bounds.minY), bounds.maxY - height)
        return CGRect(x: x, y: y, width: width, height: height)
    }
}
