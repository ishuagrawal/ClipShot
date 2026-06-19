import XCTest
@testable import ClipShot

final class AnnotationGeometryTests: XCTestCase {

    func test_hitTest_pointOnArrowSegment_hits() {
        let kind = Annotation.Kind.arrow(
            from: CGPoint(x: 0, y: 0),
            to: CGPoint(x: 100, y: 0),
            color: CGColor(gray: 0, alpha: 1),
            weight: 4
        )

        XCTAssertTrue(AnnotationGeometry.hitTest(kind, point: CGPoint(x: 50, y: 1), tolerance: 4))
    }

    func test_hitTest_pointFarFromArrow_misses() {
        let kind = Annotation.Kind.arrow(
            from: CGPoint(x: 0, y: 0),
            to: CGPoint(x: 100, y: 0),
            color: CGColor(gray: 0, alpha: 1),
            weight: 4
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
            color: CGColor(gray: 0, alpha: 1),
            weight: 2
        )

        guard case let .arrow(from, to, _, _) = AnnotationGeometry.translated(
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
            color: CGColor(gray: 0, alpha: 1),
            weight: 2
        )

        guard case let .arrow(from, to, _, _) = AnnotationGeometry.translatedClamped(
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
        let line = AnnotationGeometry.arrowLinePath(from: .zero, to: CGPoint(x: 50, y: 0), weight: 4)
        let head = AnnotationGeometry.arrowHeadPath(from: .zero, to: CGPoint(x: 50, y: 0), weight: 4)

        XCTAssertGreaterThan(line.boundingBox.width, 0)
        XCTAssertGreaterThan(head.boundingBox.width, 0)
        XCTAssertGreaterThan(head.boundingBox.height, 0)
    }
}
