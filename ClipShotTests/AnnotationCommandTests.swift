import XCTest
@testable import ClipShot

final class AnnotationCommandTests: XCTestCase {

    private func makeDoc() -> EditorDocument {
        EditorDocument(
            screenshot: TestImage.solid(.red, size: CGSize(width: 100, height: 100)),
            viewport: CGSize(width: 100, height: 100),
            pageTitle: "t",
            pageURL: "u",
            baseSelection: CGRect(x: 10, y: 10, width: 40, height: 40)
        )
    }

    private func arrow(_ id: UUID = UUID(), to: CGPoint = CGPoint(x: 20, y: 20)) -> Annotation {
        Annotation(
            id: id,
            kind: .arrow(from: .zero, to: to, color: CGColor(gray: 0, alpha: 1), weight: 3)
        )
    }

    func test_add_applyThenRevert_isIdentity() {
        var doc = makeDoc()
        let before = doc.annotations
        let command = AddAnnotationCommand(annotation: arrow())

        command.apply(to: &doc)
        XCTAssertEqual(doc.annotations.count, 1)
        command.revert(to: &doc)
        XCTAssertEqual(doc.annotations, before)
    }

    func test_remove_revertRestoresAtIndex() {
        var doc = makeDoc()
        let a = arrow()
        let b = arrow()
        let c = arrow()
        doc.annotations = [a, b, c]
        let command = RemoveAnnotationCommand(annotation: b, index: 1)

        command.apply(to: &doc)
        XCTAssertEqual(doc.annotations.map(\.id), [a.id, c.id])
        command.revert(to: &doc)
        XCTAssertEqual(doc.annotations.map(\.id), [a.id, b.id, c.id])
    }

    func test_move_applyThenRevert_isIdentity() {
        var doc = makeDoc()
        let id = UUID()
        let original = arrow(id, to: CGPoint(x: 10, y: 10))
        doc.annotations = [original]
        let moved = AnnotationGeometry.translated(original.kind, by: CGSize(width: 5, height: 5))
        let command = MoveAnnotationCommand(id: id, from: original.kind, to: moved)

        command.apply(to: &doc)
        XCTAssertEqual(doc.annotations[0].kind, moved)
        command.revert(to: &doc)
        XCTAssertEqual(doc.annotations[0].kind, original.kind)
    }

    func test_move_defaultDoesNotCoalesce() {
        let id = UUID()
        let firstKind = Annotation.Kind.arrow(
            from: .zero,
            to: CGPoint(x: 1, y: 1),
            color: CGColor(gray: 0, alpha: 1),
            weight: 2
        )
        let secondKind = Annotation.Kind.arrow(
            from: .zero,
            to: CGPoint(x: 2, y: 2),
            color: CGColor(gray: 0, alpha: 1),
            weight: 2
        )
        let first = MoveAnnotationCommand(id: id, from: firstKind, to: secondKind)
        let second = MoveAnnotationCommand(id: id, from: secondKind, to: firstKind)

        XCTAssertNil(first.coalesce(with: second))
    }

    func test_move_coalesce_sameIdAndKeyKeepsOriginalFrom() {
        let id = UUID()
        let firstKind = Annotation.Kind.arrow(
            from: .zero,
            to: CGPoint(x: 1, y: 1),
            color: CGColor(gray: 0, alpha: 1),
            weight: 2
        )
        let secondKind = Annotation.Kind.arrow(
            from: .zero,
            to: CGPoint(x: 2, y: 2),
            color: CGColor(gray: 0, alpha: 1),
            weight: 2
        )
        let thirdKind = Annotation.Kind.arrow(
            from: .zero,
            to: CGPoint(x: 3, y: 3),
            color: CGColor(gray: 0, alpha: 1),
            weight: 2
        )
        let first = MoveAnnotationCommand(id: id, from: firstKind, to: secondKind, coalescingKey: .style)
        let second = MoveAnnotationCommand(id: id, from: secondKind, to: thirdKind, coalescingKey: .style)

        let merged = first.coalesce(with: second) as? MoveAnnotationCommand

        XCTAssertNotNil(merged)
        XCTAssertEqual(merged?.from, firstKind)
        XCTAssertEqual(merged?.to, thirdKind)
    }

    func test_move_coalesce_differentIdReturnsNil() {
        let kind = Annotation.Kind.arrow(
            from: .zero,
            to: CGPoint(x: 1, y: 1),
            color: CGColor(gray: 0, alpha: 1),
            weight: 2
        )
        let first = MoveAnnotationCommand(id: UUID(), from: kind, to: kind)
        let second = MoveAnnotationCommand(id: UUID(), from: kind, to: kind)

        XCTAssertNil(first.coalesce(with: second))
    }

    func test_move_coalesce_differentKeysReturnsNil() {
        let id = UUID()
        let kind = Annotation.Kind.arrow(
            from: .zero,
            to: CGPoint(x: 1, y: 1),
            color: CGColor(gray: 0, alpha: 1),
            weight: 2
        )
        let first = MoveAnnotationCommand(id: id, from: kind, to: kind, coalescingKey: .style)
        let second = MoveAnnotationCommand(id: id, from: kind, to: kind, coalescingKey: .keyboardNudge)

        XCTAssertNil(first.coalesce(with: second))
    }

    func test_add_doesNotCoalesce() {
        let first = AddAnnotationCommand(annotation: arrow())
        let second = AddAnnotationCommand(annotation: arrow())

        XCTAssertNil(first.coalesce(with: second))
    }
}
