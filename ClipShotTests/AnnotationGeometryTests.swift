import XCTest
@testable import ClipShot

final class AnnotationGeometryTests: XCTestCase {

    func test_hitTest_pointOnArrowSegment_hits() {
        let kind = Annotation.Kind.arrow(
            from: CGPoint(x: 0, y: 0),
            to: CGPoint(x: 100, y: 0),
            pathStyle: .straight,
            curve: nil,
            color: CGColor(gray: 0, alpha: 1),
            weight: 4,
            borderColor: nil
        )

        XCTAssertTrue(AnnotationGeometry.hitTest(kind, point: CGPoint(x: 50, y: 1), tolerance: 4))
    }

    func test_hitTest_pointFarFromArrow_misses() {
        let kind = Annotation.Kind.arrow(
            from: CGPoint(x: 0, y: 0),
            to: CGPoint(x: 100, y: 0),
            pathStyle: .straight,
            curve: nil,
            color: CGColor(gray: 0, alpha: 1),
            weight: 4,
            borderColor: nil
        )

        XCTAssertFalse(AnnotationGeometry.hitTest(kind, point: CGPoint(x: 50, y: 40), tolerance: 4))
    }

    func test_hitTest_pointInsideRect_hits() {
        let kind = Annotation.Kind.rect(
            frame: CGRect(x: 10, y: 10, width: 80, height: 40),
            stroke: nil,
            fill: CGColor(gray: 1, alpha: 1),
            weight: 2,
            cornerRadius: 6
        )

        XCTAssertTrue(AnnotationGeometry.hitTest(kind, point: CGPoint(x: 40, y: 25), tolerance: 4))
        XCTAssertFalse(AnnotationGeometry.hitTest(kind, point: CGPoint(x: 200, y: 200), tolerance: 4))
    }

    func test_hitTest_pointInsideTextFrame_hits() {
        let kind = Annotation.Kind.text(
            origin: CGPoint(x: 20, y: 20),
            string: "Hello",
            fontSize: 18,
            color: CGColor(gray: 0, alpha: 1)
        )

        XCTAssertTrue(AnnotationGeometry.hitTest(kind, point: CGPoint(x: 25, y: 25), tolerance: 2))
    }

    func test_translated_arrowMovesEndpoints() {
        let kind = Annotation.Kind.arrow(
            from: CGPoint(x: 0, y: 0),
            to: CGPoint(x: 10, y: 10),
            pathStyle: .straight,
            curve: nil,
            color: CGColor(gray: 0, alpha: 1),
            weight: 2,
            borderColor: nil
        )

        guard case let .arrow(from, to, _, _, _, _, _) = AnnotationGeometry.translated(
            kind,
            by: CGSize(width: 5, height: -3)
        ) else {
            return XCTFail("expected arrow")
        }

        XCTAssertEqual(from, CGPoint(x: 5, y: -3))
        XCTAssertEqual(to, CGPoint(x: 15, y: 7))
    }

    func test_clamped_rectStaysInsideBounds() {
        let kind = Annotation.Kind.rect(
            frame: CGRect(x: -20, y: -20, width: 50, height: 50),
            stroke: nil,
            fill: nil,
            weight: 1,
            cornerRadius: 0
        )

        guard case let .rect(frame, _, _, _, _) = AnnotationGeometry.clamped(
            kind,
            to: CGRect(x: 0, y: 0, width: 100, height: 100)
        ) else {
            return XCTFail("expected rect")
        }

        XCTAssertGreaterThanOrEqual(frame.minX, 0)
        XCTAssertGreaterThanOrEqual(frame.minY, 0)
        XCTAssertLessThanOrEqual(frame.maxX, 100)
        XCTAssertLessThanOrEqual(frame.maxY, 100)
    }

    func test_translatedClamped_rectKeepsSizeWhenPushedPastBorder() {
        let kind = Annotation.Kind.rect(
            frame: CGRect(x: 10, y: 10, width: 40, height: 30),
            stroke: nil,
            fill: nil,
            weight: 0,
            cornerRadius: 0
        )

        guard case let .rect(frame, _, _, _, _) = AnnotationGeometry.translatedClamped(
            kind,
            by: CGSize(width: 1000, height: 1000),
            to: CGRect(x: 0, y: 0, width: 100, height: 100)
        ) else {
            return XCTFail("expected rect")
        }

        XCTAssertEqual(frame.size, CGSize(width: 40, height: 30))
        XCTAssertEqual(frame.maxX, 100)
        XCTAssertEqual(frame.maxY, 100)
    }

    func test_translatedClamped_arrowKeepsLengthWhenPushedPastBorder() {
        let kind = Annotation.Kind.arrow(
            from: CGPoint(x: 10, y: 10),
            to: CGPoint(x: 40, y: 10),
            pathStyle: .straight,
            curve: nil,
            color: CGColor(gray: 0, alpha: 1),
            weight: 2,
            borderColor: nil
        )

        guard case let .arrow(from, to, _, _, _, _, _) = AnnotationGeometry.translatedClamped(
            kind,
            by: CGSize(width: -1000, height: 0),
            to: CGRect(x: 0, y: 0, width: 200, height: 200)
        ) else {
            return XCTFail("expected arrow")
        }

        XCTAssertEqual(to.x - from.x, 30, accuracy: 0.001)
        XCTAssertGreaterThanOrEqual(min(from.x, to.x), 0)
    }

    func test_translatedClamped_shapeLargerThanBoundsNotResized() {
        let kind = Annotation.Kind.rect(
            frame: CGRect(x: 0, y: 0, width: 300, height: 50),
            stroke: nil,
            fill: nil,
            weight: 0,
            cornerRadius: 0
        )

        guard case let .rect(frame, _, _, _, _) = AnnotationGeometry.translatedClamped(
            kind,
            by: CGSize(width: 10, height: 5),
            to: CGRect(x: 0, y: 0, width: 100, height: 100)
        ) else {
            return XCTFail("expected rect")
        }

        XCTAssertEqual(frame.width, 300)
    }

    func test_resized_shiftSnappedArrowEndpointStaysInsideBounds() {
        let bounds = CGRect(x: 0, y: 0, width: 100, height: 100)
        let kind = Annotation.Kind.arrow(
            from: CGPoint(x: 5, y: 50),
            to: CGPoint(x: 20, y: 50),
            pathStyle: .straight,
            curve: nil,
            color: CGColor(gray: 0, alpha: 1),
            weight: 2,
            borderColor: nil
        )

        guard case let .arrow(from, to, _, _, _, _, _) = AnnotationGeometry.resized(
            kind,
            handle: .end,
            to: CGPoint(x: 100, y: 80),
            shiftLock: true,
            bounds: bounds
        ) else {
            return XCTFail("expected arrow")
        }

        XCTAssertGreaterThanOrEqual(from.x, bounds.minX)
        XCTAssertGreaterThanOrEqual(from.y, bounds.minY)
        XCTAssertLessThanOrEqual(from.x, bounds.maxX)
        XCTAssertLessThanOrEqual(from.y, bounds.maxY)
        XCTAssertGreaterThanOrEqual(to.x, bounds.minX)
        XCTAssertGreaterThanOrEqual(to.y, bounds.minY)
        XCTAssertLessThanOrEqual(to.x, bounds.maxX)
        XCTAssertLessThanOrEqual(to.y, bounds.maxY)
    }

    func test_resizedTextDoesNotExceedBounds() {
        let bounds = CGRect(x: 0, y: 0, width: 120, height: 120)
        let kind = Annotation.Kind.text(
            origin: CGPoint(x: 10, y: 10),
            string: "Long text that should stay inside bounds",
            fontSize: 18,
            color: CGColor(gray: 0, alpha: 1)
        )

        let resized = AnnotationGeometry.resized(
            kind,
            handle: .scaleBottomRight,
            to: CGPoint(x: 500, y: 500),
            shiftLock: false,
            bounds: bounds
        )
        let frame = AnnotationGeometry.boundingBox(resized)

        XCTAssertLessThanOrEqual(frame.width, bounds.width)
        XCTAssertLessThanOrEqual(frame.height, bounds.height)
        XCTAssertGreaterThanOrEqual(frame.minX, bounds.minX)
        XCTAssertGreaterThanOrEqual(frame.minY, bounds.minY)
        XCTAssertLessThanOrEqual(frame.maxX, bounds.maxX)
        XCTAssertLessThanOrEqual(frame.maxY, bounds.maxY)
    }

    func test_textFrame_emptyStringHasSelectableSize() {
        let frame = AnnotationGeometry.textFrame(origin: .zero, string: "", fontSize: 20)

        XCTAssertGreaterThan(frame.width, 0)
        XCTAssertGreaterThan(frame.height, 0)
    }

    func test_hitTest_pointOnLineSegment_hits() {
        let kind = Annotation.Kind.line(
            from: CGPoint(x: 0, y: 0),
            to: CGPoint(x: 100, y: 0),
            color: CGColor(gray: 0, alpha: 1),
            weight: 4,
            dash: .solid
        )

        XCTAssertTrue(AnnotationGeometry.hitTest(kind, point: CGPoint(x: 50, y: 1), tolerance: 4))
        XCTAssertFalse(AnnotationGeometry.hitTest(kind, point: CGPoint(x: 50, y: 40), tolerance: 4))
    }

    func test_boundingBox_lineCoversSegment() {
        let kind = Annotation.Kind.line(
            from: CGPoint(x: 10, y: 20),
            to: CGPoint(x: 60, y: 20),
            color: CGColor(gray: 0, alpha: 1),
            weight: 4,
            dash: .dashed
        )

        let box = AnnotationGeometry.boundingBox(kind)
        XCTAssertLessThanOrEqual(box.minX, 10)
        XCTAssertGreaterThanOrEqual(box.maxX, 60)
    }

    func test_dashStyle_dottedUsesRoundCap() {
        XCTAssertEqual(AnnotationGeometry.dashStyle(.solid, weight: 4).cap, .butt)
        XCTAssertNil(AnnotationGeometry.dashStyle(.solid, weight: 4).pattern)
        XCTAssertEqual(AnnotationGeometry.dashStyle(.dotted, weight: 4).cap, .round)
        XCTAssertNotNil(AnnotationGeometry.dashStyle(.dashed, weight: 4).pattern)
    }

    func test_arrowPathsAreNonEmpty() {
        let straightLine = AnnotationGeometry.arrowShaftPath(from: .zero, to: CGPoint(x: 50, y: 0), curve: nil, weight: 4)
        let straightHead = AnnotationGeometry.arrowHeadPath(from: .zero, to: CGPoint(x: 50, y: 0), curve: nil, weight: 4)
        let control = AnnotationGeometry.defaultCurveControl(from: .zero, to: CGPoint(x: 50, y: 0))
        let curvedLine = AnnotationGeometry.arrowShaftPath(from: .zero, to: CGPoint(x: 50, y: 0), curve: control, weight: 4)
        let curvedHead = AnnotationGeometry.arrowHeadPath(from: .zero, to: CGPoint(x: 50, y: 0), curve: control, weight: 4)

        XCTAssertGreaterThan(straightLine.boundingBox.width, 0)
        XCTAssertGreaterThan(straightHead.boundingBox.width, 0)
        XCTAssertGreaterThan(straightHead.boundingBox.height, 0)
        XCTAssertGreaterThan(curvedLine.boundingBox.width, 0)
        XCTAssertGreaterThan(curvedHead.boundingBox.width, 0)
        XCTAssertGreaterThan(curvedHead.boundingBox.height, 0)
    }

    func test_hitTest_pointOnCurvedArrow_hits() {
        let from = CGPoint(x: 0, y: 0)
        let to = CGPoint(x: 100, y: 0)
        let control = AnnotationGeometry.defaultCurveControl(from: from, to: to)
        let kind = Annotation.Kind.arrow(
            from: from,
            to: to,
            pathStyle: .curved,
            curve: control,
            color: CGColor(gray: 0, alpha: 1),
            weight: 4,
            borderColor: nil
        )

        XCTAssertTrue(AnnotationGeometry.hitTest(kind, point: CGPoint(x: 50, y: 18), tolerance: 4))
    }

    func test_resize_curveHandleMovesPointOnCurve() {
        let from = CGPoint(x: 10, y: 10)
        let to = CGPoint(x: 90, y: 10)
        let control = AnnotationGeometry.defaultCurveControl(from: from, to: to)
        let kind = Annotation.Kind.arrow(
            from: from,
            to: to,
            pathStyle: .curved,
            curve: control,
            color: CGColor(gray: 0, alpha: 1),
            weight: 4,
            borderColor: nil
        )
        let bounds = CGRect(x: 0, y: 0, width: 200, height: 200)
        let target = CGPoint(x: 50, y: 30)

        guard case let .arrow(_, _, _, movedControl, _, _, _) = AnnotationGeometry.resized(
            kind,
            handle: .curve,
            to: target,
            shiftLock: false,
            bounds: bounds
        ) else {
            return XCTFail("expected arrow")
        }

        let movedHandle = AnnotationGeometry.arrowCurveHandlePoint(
            from: from,
            control: movedControl!,
            to: to
        )
        XCTAssertEqual(movedHandle.x, target.x, accuracy: 0.001)
        XCTAssertEqual(movedHandle.y, target.y, accuracy: 0.001)
    }

    func test_curveHandleSitsOnCurveNotBezierControl() {
        let from = CGPoint(x: 0, y: 0)
        let to = CGPoint(x: 100, y: 0)
        let control = AnnotationGeometry.defaultCurveControl(from: from, to: to)
        let handle = AnnotationGeometry.arrowCurveHandlePoint(from: from, control: control, to: to)

        XCTAssertGreaterThan(hypot(handle.x - control.x, handle.y - control.y), 1)
        XCTAssertLessThan(abs(handle.y - 16), 1)
    }

    func test_curvedArrowShaftMeetsHeadBase() {
        let from = CGPoint(x: 10, y: 10)
        let to = CGPoint(x: 90, y: 70)
        let control = AnnotationGeometry.defaultCurveControl(from: from, to: to)
        let weight: CGFloat = 8
        let head = AnnotationGeometry.arrowHeadLength(weight: weight)
        let shaft = AnnotationGeometry.arrowShaftPath(from: from, to: to, curve: control, weight: weight)
        let headPath = AnnotationGeometry.arrowHeadPath(from: from, to: to, curve: control, weight: weight)

        let shaftEnd = pathEndPoint(shaft)
        let headLeft = pathInteriorPoint(headPath, index: 1)
        let headRight = pathInteriorPoint(headPath, index: 2)
        let headBase = CGPoint(
            x: (headLeft.x + headRight.x) / 2,
            y: (headLeft.y + headRight.y) / 2
        )

        XCTAssertEqual(hypot(shaftEnd.x - to.x, shaftEnd.y - to.y), head, accuracy: 0.75)
        XCTAssertEqual(hypot(headBase.x - to.x, headBase.y - to.y), head, accuracy: 0.75)
        XCTAssertEqual(shaftEnd.x, headBase.x, accuracy: 1.5)
        XCTAssertEqual(shaftEnd.y, headBase.y, accuracy: 1.5)
    }

    func test_shortCurvedArrowShaftFallsBackToTip() {
        let from = CGPoint(x: 10, y: 10)
        let to = CGPoint(x: 18, y: 10)
        let control = AnnotationGeometry.defaultCurveControl(from: from, to: to)
        let shaft = AnnotationGeometry.arrowShaftPath(from: from, to: to, curve: control, weight: 8)

        let shaftEnd = pathEndPoint(shaft)

        XCTAssertEqual(shaftEnd.x, to.x, accuracy: 0.001)
        XCTAssertEqual(shaftEnd.y, to.y, accuracy: 0.001)
    }

    func test_curvedArrowBoundingBoxStaysNearCurveApex() {
        let from = CGPoint(x: 0, y: 0)
        let to = CGPoint(x: 100, y: 0)
        let control = AnnotationGeometry.defaultCurveControl(from: from, to: to)
        let handle = AnnotationGeometry.arrowCurveHandlePoint(from: from, control: control, to: to)
        let kind = Annotation.Kind.arrow(
            from: from,
            to: to,
            pathStyle: .curved,
            curve: control,
            color: CGColor(gray: 0, alpha: 1),
            weight: 4,
            borderColor: nil
        )

        let box = AnnotationGeometry.boundingBox(kind)
        XCTAssertTrue(box.contains(handle))
        XCTAssertLessThan(box.maxY - handle.y, 18)
        XCTAssertLessThan(box.maxY, control.y)
    }

    func test_straighteningCurvedArrowPreservesCurveControl() {
        let from = CGPoint(x: 10, y: 10)
        let to = CGPoint(x: 90, y: 40)
        let control = CGPoint(x: 40, y: 80)
        let curved = Annotation.Kind.arrow(
            from: from,
            to: to,
            pathStyle: .curved,
            curve: control,
            color: CGColor(gray: 0, alpha: 1),
            weight: 4,
            borderColor: nil
        )
        let straight = Annotation.Kind.arrow(
            from: from,
            to: to,
            pathStyle: .straight,
            curve: control,
            color: CGColor(gray: 0, alpha: 1),
            weight: 4,
            borderColor: nil
        )
        let restored = Annotation.Kind.arrow(
            from: from,
            to: to,
            pathStyle: .curved,
            curve: control,
            color: CGColor(gray: 0, alpha: 1),
            weight: 4,
            borderColor: nil
        )

        guard case let .arrow(_, _, .straight, preserved, _, _, _) = straight,
              case let .arrow(_, _, .curved, restoredCurve, _, _, _) = restored else {
            return XCTFail("expected arrow kinds")
        }

        XCTAssertEqual(preserved, control)
        XCTAssertEqual(restoredCurve, control)
        XCTAssertEqual(curved, restored)
    }
}

private func pathEndPoint(_ path: CGPath) -> CGPoint {
    var point = CGPoint.zero
    var didMove = false
    path.applyWithBlock { element in
        switch element.pointee.type {
        case .moveToPoint, .addLineToPoint:
            point = element.pointee.points[0]
            didMove = true
        case .addQuadCurveToPoint:
            point = element.pointee.points[1]
            didMove = true
        case .addCurveToPoint:
            point = element.pointee.points[2]
            didMove = true
        default:
            break
        }
    }
    precondition(didMove)
    return point
}

private func pathInteriorPoint(_ path: CGPath, index: Int) -> CGPoint {
    var points: [CGPoint] = []
    path.applyWithBlock { element in
        switch element.pointee.type {
        case .moveToPoint, .addLineToPoint:
            points.append(element.pointee.points[0])
        default:
            break
        }
    }
    precondition(points.count > index)
    return points[index]
}
