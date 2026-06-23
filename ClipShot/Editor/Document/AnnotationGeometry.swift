import CoreGraphics
import CoreText
import Foundation

/// A draggable resize control on a selected annotation. Endpoints for
/// arrow/line, eight box controls for rect/blur, four scaling corners for text.
enum ResizeHandle {
    case start, end, curve
    case topLeft, top, topRight, right, bottomRight, bottom, bottomLeft, left
    case scaleTopLeft, scaleTopRight, scaleBottomLeft, scaleBottomRight
}

/// Pure geometry shared by export rendering and the canvas preview. All values
/// are selection-relative annotation coordinates: top-left origin, y-down,
/// one point per image pixel, with (0, 0) at `EditorDocument.baseSelection`.
enum AnnotationGeometry {

    static func arrowHeadLength(weight: CGFloat) -> CGFloat {
        max(10, weight * 3.5)
    }

    static func arrowBorderWidth(weight: CGFloat) -> CGFloat {
        max(2, weight * 0.5)
    }

    static func arrowCurve(pathStyle: Annotation.ArrowPathStyle, curve: CGPoint?) -> CGPoint? {
        pathStyle == .curved ? curve : nil
    }

    /// Default bow places the visible arc apex ~16% of the chord length off-center.
    static func defaultCurveControl(from: CGPoint, to: CGPoint) -> CGPoint {
        arrowCurveControl(
            from: from,
            to: to,
            handle: defaultCurveHandle(from: from, to: to)
        )
    }

    /// Handle anchor on the drawn curve (t = 0.5), not the off-curve bezier control.
    static func arrowCurveHandlePoint(from: CGPoint, control: CGPoint, to: CGPoint) -> CGPoint {
        quadPoint(from: from, control: control, to: to, t: 0.5)
    }

    static func arrowCurveControl(from: CGPoint, to: CGPoint, handle: CGPoint) -> CGPoint {
        let mid = CGPoint(x: (from.x + to.x) / 2, y: (from.y + to.y) / 2)
        return CGPoint(
            x: 2 * handle.x - mid.x,
            y: 2 * handle.y - mid.y
        )
    }

    private static func defaultCurveHandle(from: CGPoint, to: CGPoint) -> CGPoint {
        let mid = CGPoint(x: (from.x + to.x) / 2, y: (from.y + to.y) / 2)
        let dx = to.x - from.x
        let dy = to.y - from.y
        let length = max(hypot(dx, dy), 0.0001)
        let bow = length * 0.16
        let perpendicular = CGPoint(x: -dy / length, y: dx / length)
        return CGPoint(x: mid.x + perpendicular.x * bow, y: mid.y + perpendicular.y * bow)
    }

    private static func arrowRenderedBounds(
        from: CGPoint,
        to: CGPoint,
        curve: CGPoint?,
        weight: CGFloat
    ) -> CGRect {
        let head = arrowHeadPath(from: from, to: to, curve: curve, weight: weight)
        let shaftBounds: CGRect
        if let curve {
            // CGPath.boundingBox expands quad curves to include the off-curve control.
            shaftBounds = arrowCurvedShaftBounds(from: from, to: to, control: curve, weight: weight)
        } else {
            shaftBounds = arrowStraightShaftPath(from: from, to: to, weight: weight).boundingBox
        }
        return shaftBounds.union(head.boundingBox)
    }

    private static func arrowCurvedShaftBounds(
        from: CGPoint,
        to: CGPoint,
        control: CGPoint,
        weight: CGFloat
    ) -> CGRect {
        var box = CGRect.null
        let steps = 24
        for step in 0...steps {
            let t = CGFloat(step) / CGFloat(steps)
            let point = quadPoint(from: from, control: control, to: to, t: t)
            box = box.union(CGRect(x: point.x, y: point.y, width: 0, height: 0))
        }
        let strokePad = weight / 2
        return box.insetBy(dx: -strokePad, dy: -strokePad)
    }

    static func arrowShaftPath(from: CGPoint, to: CGPoint, curve: CGPoint?, weight: CGFloat) -> CGPath {
        if let curve {
            return arrowCurveShaftPath(from: from, to: to, control: curve, weight: weight)
        }
        return arrowStraightShaftPath(from: from, to: to, weight: weight)
    }

    static func arrowHeadPath(from: CGPoint, to: CGPoint, curve: CGPoint?, weight: CGFloat) -> CGPath {
        if let curve {
            return arrowCurveHeadPath(from: from, to: to, control: curve, weight: weight)
        }
        return arrowStraightHeadPath(from: from, to: to, weight: weight)
    }

    private static func arrowStraightShaftPath(from: CGPoint, to: CGPoint, weight: CGFloat) -> CGPath {
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

    private static func arrowStraightHeadPath(from: CGPoint, to: CGPoint, weight: CGFloat) -> CGPath {
        arrowHeadPath(
            at: to,
            direction: CGPoint(x: to.x - from.x, y: to.y - from.y),
            weight: weight
        )
    }

    private static func arrowCurveShaftPath(
        from: CGPoint,
        to: CGPoint,
        control: CGPoint,
        weight: CGFloat
    ) -> CGPath {
        let head = arrowHeadLength(weight: weight)
        let junction = arrowCurveJunction(from: from, control: control, to: to, headLength: head)
        let path = CGMutablePath()
        path.move(to: from)
        if junction.t <= 0.001 || junction.t >= 1 {
            path.addQuadCurve(to: to, control: control)
        } else {
            let segment = subdivideQuad(from: from, control: control, to: to, at: junction.t)
            path.addQuadCurve(to: segment.end, control: segment.control)
        }
        return path
    }

    private static func arrowCurveHeadPath(
        from: CGPoint,
        to: CGPoint,
        control: CGPoint,
        weight: CGFloat
    ) -> CGPath {
        let head = arrowHeadLength(weight: weight)
        let junction = arrowCurveJunction(from: from, control: control, to: to, headLength: head)
        let dx = to.x - junction.point.x
        let dy = to.y - junction.point.y
        let direction: CGPoint
        if hypot(dx, dy) < 0.5 {
            direction = CGPoint(x: to.x - control.x, y: to.y - control.y)
        } else {
            direction = CGPoint(x: dx, y: dy)
        }
        return arrowHeadPath(at: to, direction: direction, weight: weight)
    }

    /// Point on the curve `headLength` pixels from the tip, shared by the shaft end and head base.
    private static func arrowCurveJunction(
        from: CGPoint,
        control: CGPoint,
        to: CGPoint,
        headLength: CGFloat
    ) -> (t: CGFloat, point: CGPoint) {
        let trimT = curveParameterAtEuclideanDistanceFromEnd(
            from: from,
            control: control,
            to: to,
            distance: headLength
        )
        let point = quadPoint(from: from, control: control, to: to, t: trimT)
        return (trimT, point)
    }

    private static func curveParameterAtEuclideanDistanceFromEnd(
        from: CGPoint,
        control: CGPoint,
        to: CGPoint,
        distance: CGFloat
    ) -> CGFloat {
        var low: CGFloat = 0
        var high: CGFloat = 1
        for _ in 0..<24 {
            let mid = (low + high) / 2
            let point = quadPoint(from: from, control: control, to: to, t: mid)
            let separation = hypot(point.x - to.x, point.y - to.y)
            if separation > distance {
                low = mid
            } else {
                high = mid
            }
        }
        return (low + high) / 2
    }

    private static func arrowHeadPath(at tip: CGPoint, direction: CGPoint, weight: CGFloat) -> CGPath {
        let head = arrowHeadLength(weight: weight)
        let length = max(hypot(direction.x, direction.y), 0.0001)
        let unit = CGPoint(x: direction.x / length, y: direction.y / length)
        let base = CGPoint(x: tip.x - unit.x * head, y: tip.y - unit.y * head)
        let halfWidth = head * 0.55
        let perpendicular = CGPoint(x: -unit.y, y: unit.x)
        let left = CGPoint(x: base.x + perpendicular.x * halfWidth, y: base.y + perpendicular.y * halfWidth)
        let right = CGPoint(x: base.x - perpendicular.x * halfWidth, y: base.y - perpendicular.y * halfWidth)

        let path = CGMutablePath()
        path.move(to: tip)
        path.addLine(to: left)
        path.addLine(to: right)
        path.closeSubpath()
        return path
    }

    private static func quadPoint(
        from: CGPoint,
        control: CGPoint,
        to: CGPoint,
        t: CGFloat
    ) -> CGPoint {
        let oneMinusT = 1 - t
        let a = CGPoint(
            x: oneMinusT * from.x + t * control.x,
            y: oneMinusT * from.y + t * control.y
        )
        let b = CGPoint(
            x: oneMinusT * control.x + t * to.x,
            y: oneMinusT * control.y + t * to.y
        )
        return CGPoint(
            x: oneMinusT * a.x + t * b.x,
            y: oneMinusT * a.y + t * b.y
        )
    }

    private static func subdivideQuad(
        from: CGPoint,
        control: CGPoint,
        to: CGPoint,
        at t: CGFloat
    ) -> (control: CGPoint, end: CGPoint) {
        let a = CGPoint(
            x: from.x + (control.x - from.x) * t,
            y: from.y + (control.y - from.y) * t
        )
        let b = CGPoint(
            x: control.x + (to.x - control.x) * t,
            y: control.y + (to.y - control.y) * t
        )
        let end = CGPoint(
            x: a.x + (b.x - a.x) * t,
            y: a.y + (b.y - a.y) * t
        )
        return (a, end)
    }

    private static func distanceToQuadCurve(
        _ point: CGPoint,
        from: CGPoint,
        control: CGPoint,
        to: CGPoint
    ) -> CGFloat {
        let steps = 32
        var minimum = CGFloat.greatestFiniteMagnitude
        var previous = from
        for step in 1...steps {
            let t = CGFloat(step) / CGFloat(steps)
            let sample = quadPoint(from: from, control: control, to: to, t: t)
            minimum = min(minimum, distance(point, segmentStart: previous, segmentEnd: sample))
            previous = sample
        }
        return minimum
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
        case .arrow(let from, let to, let pathStyle, let curve, _, let weight, _):
            let activeCurve = arrowCurve(pathStyle: pathStyle, curve: curve)
            let box = arrowRenderedBounds(from: from, to: to, curve: activeCurve, weight: weight)
            let pad = activeCurve == nil
                ? arrowHeadLength(weight: weight) * 0.6 + weight
                : max(3, weight / 2)
            return box.insetBy(dx: -pad, dy: -pad)
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
        case .arrow(let from, let to, let pathStyle, let curve, _, let weight, _):
            let distanceToShaft: CGFloat
            if let activeCurve = arrowCurve(pathStyle: pathStyle, curve: curve) {
                distanceToShaft = distanceToQuadCurve(point, from: from, control: activeCurve, to: to)
            } else {
                distanceToShaft = distance(point, segmentStart: from, segmentEnd: to)
            }
            return distanceToShaft <= tolerance + weight / 2
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

    static let minResizeSize: CGFloat = 6

    /// Resize-handle anchor points in annotation coordinates, in draw order.
    static func resizeHandles(_ kind: Annotation.Kind) -> [(handle: ResizeHandle, point: CGPoint)] {
        switch kind {
        case .arrow(let from, let to, let pathStyle, let curve, _, _, _):
            var handles: [(ResizeHandle, CGPoint)] = [(.start, from), (.end, to)]
            if let activeCurve = arrowCurve(pathStyle: pathStyle, curve: curve) {
                handles.append((
                    .curve,
                    arrowCurveHandlePoint(from: from, control: activeCurve, to: to)
                ))
            }
            return handles
        case .line(let from, let to, _, _, _):
            return [(.start, from), (.end, to)]
        case .rect(let frame, _, _, _, _), .blur(let frame, _):
            return boxHandles(frame.standardized)
        case .text(let origin, let string, let fontSize, _):
            let f = textFrame(origin: origin, string: string, fontSize: fontSize)
            return [
                (.scaleTopLeft, CGPoint(x: f.minX, y: f.minY)),
                (.scaleTopRight, CGPoint(x: f.maxX, y: f.minY)),
                (.scaleBottomLeft, CGPoint(x: f.minX, y: f.maxY)),
                (.scaleBottomRight, CGPoint(x: f.maxX, y: f.maxY))
            ]
        }
    }

    private static func boxHandles(_ f: CGRect) -> [(ResizeHandle, CGPoint)] {
        [
            (.topLeft, CGPoint(x: f.minX, y: f.minY)),
            (.top, CGPoint(x: f.midX, y: f.minY)),
            (.topRight, CGPoint(x: f.maxX, y: f.minY)),
            (.right, CGPoint(x: f.maxX, y: f.midY)),
            (.bottomRight, CGPoint(x: f.maxX, y: f.maxY)),
            (.bottom, CGPoint(x: f.midX, y: f.maxY)),
            (.bottomLeft, CGPoint(x: f.minX, y: f.maxY)),
            (.left, CGPoint(x: f.minX, y: f.midY))
        ]
    }

    /// New kind for `handle` dragged to `point`. Clamps to `bounds`, enforces a
    /// minimum size (never flips), and aspect-locks box corners when `shiftLock`.
    static func resized(
        _ kind: Annotation.Kind,
        handle: ResizeHandle,
        to point: CGPoint,
        shiftLock: Bool,
        bounds: CGRect
    ) -> Annotation.Kind {
        switch kind {
        case .arrow(let from, let to, let pathStyle, let curve, let color, let weight, let borderColor):
            switch handle {
            case .curve:
                guard arrowCurve(pathStyle: pathStyle, curve: curve) != nil else { return kind }
                return .arrow(
                    from: from,
                    to: to,
                    pathStyle: pathStyle,
                    curve: arrowCurveControl(
                        from: from,
                        to: to,
                        handle: point.clamped(to: bounds)
                    ),
                    color: color,
                    weight: weight,
                    borderColor: borderColor
                )
            default:
                let (f, t) = resizedEndpoints(
                    from: from,
                    to: to,
                    handle: handle,
                    to: point,
                    shiftLock: shiftLock,
                    snapAxis: false,
                    bounds: bounds
                )
                return .arrow(
                    from: f,
                    to: t,
                    pathStyle: pathStyle,
                    curve: curve,
                    color: color,
                    weight: weight,
                    borderColor: borderColor
                )
            }
        case .line(let from, let to, let color, let weight, let dash):
            let (f, t) = resizedEndpoints(from: from, to: to, handle: handle, to: point, shiftLock: shiftLock, snapAxis: true, bounds: bounds)
            return .line(from: f, to: t, color: color, weight: weight, dash: dash)
        case .rect(let frame, let stroke, let fill, let weight, let corner):
            let f = resizedBox(frame.standardized, handle: handle, to: point, shiftLock: shiftLock, bounds: bounds)
            return .rect(frame: f, stroke: stroke, fill: fill, weight: weight, cornerRadius: corner)
        case .blur(let frame, let radius):
            let f = resizedBox(frame.standardized, handle: handle, to: point, shiftLock: shiftLock, bounds: bounds)
            return .blur(frame: f, radius: radius)
        case .text(let origin, let string, let fontSize, let color):
            let (o, size) = resizedText(origin: origin, string: string, fontSize: fontSize, handle: handle, to: point, bounds: bounds)
            return .text(origin: o, string: string, fontSize: size, color: color)
        }
    }

    private static func resizedEndpoints(
        from: CGPoint, to: CGPoint, handle: ResizeHandle, to point: CGPoint,
        shiftLock: Bool, snapAxis: Bool, bounds: CGRect
    ) -> (CGPoint, CGPoint) {
        let p = point.clamped(to: bounds)
        switch handle {
        case .start:
            return (snappedEndpoint(anchor: to, moving: p, shiftLock: shiftLock, snapAxis: snapAxis).clamped(to: bounds), to)
        case .end:
            return (from, snappedEndpoint(anchor: from, moving: p, shiftLock: shiftLock, snapAxis: snapAxis).clamped(to: bounds))
        default:
            return (from, to)
        }
    }

    private static func snappedEndpoint(anchor: CGPoint, moving: CGPoint, shiftLock: Bool, snapAxis: Bool) -> CGPoint {
        if shiftLock { return snap45(from: anchor, to: moving) }
        return snapAxis ? snapNearAxis(from: anchor, to: moving) : moving
    }

    private static func isBoxCorner(_ handle: ResizeHandle) -> Bool {
        switch handle {
        case .topLeft, .topRight, .bottomLeft, .bottomRight: return true
        default: return false
        }
    }

    private static func resizedBox(_ frame: CGRect, handle: ResizeHandle, to point: CGPoint, shiftLock: Bool, bounds: CGRect) -> CGRect {
        let p = point.clamped(to: bounds)
        var minX = frame.minX, minY = frame.minY, maxX = frame.maxX, maxY = frame.maxY

        let movesLeft = handle == .topLeft || handle == .left || handle == .bottomLeft
        let movesRight = handle == .topRight || handle == .right || handle == .bottomRight
        let movesTop = handle == .topLeft || handle == .top || handle == .topRight
        let movesBottom = handle == .bottomLeft || handle == .bottom || handle == .bottomRight

        if movesLeft { minX = min(p.x, maxX - minResizeSize) }
        if movesRight { maxX = max(p.x, minX + minResizeSize) }
        if movesTop { minY = min(p.y, maxY - minResizeSize) }
        if movesBottom { maxY = max(p.y, minY + minResizeSize) }

        let result = CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
        guard shiftLock, isBoxCorner(handle) else { return result }
        return aspectLockedBox(result, original: frame, handle: handle, bounds: bounds)
    }

    private static func aspectLockedBox(_ proposed: CGRect, original: CGRect, handle: ResizeHandle, bounds: CGRect) -> CGRect {
        guard original.width > 0, original.height > 0 else { return proposed }
        let aspect = original.width / original.height
        var w = max(proposed.width, minResizeSize)
        var h = max(proposed.height, minResizeSize)
        if w / h > aspect { h = w / aspect } else { w = h * aspect }

        let anchor: CGPoint
        switch handle {
        case .topLeft:     anchor = CGPoint(x: original.maxX, y: original.maxY)
        case .topRight:    anchor = CGPoint(x: original.minX, y: original.maxY)
        case .bottomLeft:  anchor = CGPoint(x: original.maxX, y: original.minY)
        case .bottomRight: anchor = CGPoint(x: original.minX, y: original.minY)
        default: return proposed
        }

        let availW: CGFloat
        let availH: CGFloat
        switch handle {
        case .topLeft:     availW = anchor.x - bounds.minX; availH = anchor.y - bounds.minY
        case .topRight:    availW = bounds.maxX - anchor.x; availH = anchor.y - bounds.minY
        case .bottomLeft:  availW = anchor.x - bounds.minX; availH = bounds.maxY - anchor.y
        case .bottomRight: availW = bounds.maxX - anchor.x; availH = bounds.maxY - anchor.y
        default:           availW = .infinity; availH = .infinity
        }
        if w > availW { w = availW; h = w / aspect }
        if h > availH { h = availH; w = h * aspect }

        let x = (handle == .topLeft || handle == .bottomLeft) ? anchor.x - w : anchor.x
        let y = (handle == .topLeft || handle == .topRight) ? anchor.y - h : anchor.y
        return CGRect(x: x, y: y, width: w, height: h)
    }

    private static func resizedText(
        origin: CGPoint, string: String, fontSize: CGFloat,
        handle: ResizeHandle, to point: CGPoint, bounds: CGRect
    ) -> (CGPoint, CGFloat) {
        let frame = textFrame(origin: origin, string: string, fontSize: fontSize)
        let anchor: CGPoint
        switch handle {
        case .scaleTopLeft:     anchor = CGPoint(x: frame.maxX, y: frame.maxY)
        case .scaleTopRight:    anchor = CGPoint(x: frame.minX, y: frame.maxY)
        case .scaleBottomLeft:  anchor = CGPoint(x: frame.maxX, y: frame.minY)
        case .scaleBottomRight: anchor = CGPoint(x: frame.minX, y: frame.minY)
        default: return (origin, fontSize)
        }

        let p = point.clamped(to: bounds)
        let oldDist = hypot(frame.width, frame.height)
        let newDist = hypot(p.x - anchor.x, p.y - anchor.y)
        guard oldDist > 0.0001 else { return (origin, fontSize) }
        let desiredSize = min(max(fontSize * (newDist / oldDist), 8), 400)
        let newSize = fittedTextFontSize(
            string: string,
            desiredSize: desiredSize,
            available: textResizeAvailableSize(anchor: anchor, handle: handle, bounds: bounds)
        )

        let measured = textFrame(origin: .zero, string: string, fontSize: newSize)
        let left = handle == .scaleTopLeft || handle == .scaleBottomLeft
        let top = handle == .scaleTopLeft || handle == .scaleTopRight
        var newOrigin = CGPoint(
            x: left ? anchor.x - measured.width : anchor.x,
            y: top ? anchor.y - measured.height : anchor.y
        )
        newOrigin.x = min(max(newOrigin.x, bounds.minX), max(bounds.minX, bounds.maxX - measured.width))
        newOrigin.y = min(max(newOrigin.y, bounds.minY), max(bounds.minY, bounds.maxY - measured.height))
        return (newOrigin, newSize)
    }

    private static func textResizeAvailableSize(anchor: CGPoint, handle: ResizeHandle, bounds: CGRect) -> CGSize {
        let left = handle == .scaleTopLeft || handle == .scaleBottomLeft
        let top = handle == .scaleTopLeft || handle == .scaleTopRight
        return CGSize(
            width: left ? anchor.x - bounds.minX : bounds.maxX - anchor.x,
            height: top ? anchor.y - bounds.minY : bounds.maxY - anchor.y
        )
    }

    private static func fittedTextFontSize(string: String, desiredSize: CGFloat, available: CGSize) -> CGFloat {
        guard available.width > 0, available.height > 0 else { return desiredSize }
        let fits: (CGFloat) -> Bool = { size in
            let frame = textFrame(origin: .zero, string: string, fontSize: size)
            return frame.width <= available.width && frame.height <= available.height
        }
        guard !fits(desiredSize) else { return desiredSize }

        let normalMinimum: CGFloat = 8
        let floorSize: CGFloat = fits(normalMinimum) ? normalMinimum : 1
        var low: CGFloat = floorSize
        var high: CGFloat = desiredSize
        for _ in 0..<18 {
            let mid = (low + high) / 2
            if fits(mid) {
                low = mid
            } else {
                high = mid
            }
        }
        return low
    }

    /// Auto-lock to horizontal or vertical when the segment is within ~7° of an
    /// axis. Shared by creation and resize so lines straighten the same way.
    static func snapNearAxis(from: CGPoint, to: CGPoint) -> CGPoint {
        let dx = to.x - from.x
        let dy = to.y - from.y
        guard hypot(dx, dy) > 0.0001 else { return to }
        let threshold = 7.0 * .pi / 180
        let angle = atan2(abs(dy), abs(dx))
        if angle <= threshold { return CGPoint(x: to.x, y: from.y) }
        if angle >= .pi / 2 - threshold { return CGPoint(x: from.x, y: to.y) }
        return to
    }

    static func snap45(from: CGPoint, to: CGPoint) -> CGPoint {
        let dx = to.x - from.x
        let dy = to.y - from.y
        let angle = atan2(dy, dx)
        let snapped = (angle / (.pi / 4)).rounded() * (.pi / 4)
        let length = hypot(dx, dy)
        return CGPoint(x: from.x + cos(snapped) * length, y: from.y + sin(snapped) * length)
    }

    static func translated(_ kind: Annotation.Kind, by delta: CGSize) -> Annotation.Kind {
        switch kind {
        case .arrow(let from, let to, let pathStyle, let curve, let color, let weight, let borderColor):
            return .arrow(
                from: from.offset(delta),
                to: to.offset(delta),
                pathStyle: pathStyle,
                curve: curve?.offset(delta),
                color: color,
                weight: weight,
                borderColor: borderColor
            )
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
        case .arrow(let from, let to, let pathStyle, let curve, _, let weight, _):
            return arrowRenderedBounds(
                from: from,
                to: to,
                curve: arrowCurve(pathStyle: pathStyle, curve: curve),
                weight: weight
            )
        case .line(let from, let to, _, _, _):
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
        case .arrow(let from, let to, let pathStyle, let curve, let color, let weight, let borderColor):
            return .arrow(
                from: from.clamped(to: bounds),
                to: to.clamped(to: bounds),
                pathStyle: pathStyle,
                curve: curve?.clamped(to: bounds),
                color: color,
                weight: weight,
                borderColor: borderColor
            )
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
