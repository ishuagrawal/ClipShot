import XCTest
@testable import ClipShot

final class CommandTests: XCTestCase {

    private func makeDoc() -> EditorDocument {
        EditorDocument(
            screenshot: TestImage.solid(.red, size: CGSize(width: 100, height: 100)),
            viewport: CGSize(width: 100, height: 100),
            sourceTitle: "t",
            sourceURL: "u",
            baseSelection: CGRect(x: 10, y: 10, width: 40, height: 40)
        )
    }

    func test_setPadding_applyThenRevert_isIdentity() {
        var doc = makeDoc()
        let before = doc.padding
        let target = PaddingConfig(top: 8, right: 8, bottom: 8, left: 8)
        let command = SetPaddingCommand(from: doc.padding, to: target)

        command.apply(to: &doc)
        XCTAssertEqual(doc.padding, target)
        command.revert(to: &doc)
        XCTAssertEqual(doc.padding, before)
    }

    func test_setCardCorner_applyThenRevert_isIdentity() {
        var doc = makeDoc()
        let before = doc.cardCornerOverride
        let command = SetCardCornerCommand(from: before, to: 24)

        command.apply(to: &doc)
        XCTAssertEqual(doc.cardCornerOverride, 24)
        command.revert(to: &doc)
        XCTAssertEqual(doc.cardCornerOverride, before)
    }

    func test_setCardCorner_revertRestoresAutoNil() {
        var doc = makeDoc()
        doc.cardCornerOverride = 30
        let command = SetCardCornerCommand(from: 30, to: nil)

        command.apply(to: &doc)
        XCTAssertNil(doc.cardCornerOverride)
        command.revert(to: &doc)
        XCTAssertEqual(doc.cardCornerOverride, 30)
    }

    func test_setCardCorner_coalesce_keepsOriginalFrom() {
        let first = SetCardCornerCommand(from: nil, to: 10)
        let second = SetCardCornerCommand(from: 10, to: 40)

        let merged = first.coalesce(with: second) as? SetCardCornerCommand
        XCTAssertNotNil(merged)
        XCTAssertEqual(merged?.from, nil)
        XCTAssertEqual(merged?.to, 40)
    }

    func test_setPadding_coalesce_keepsOriginalFrom() {
        let first = SetPaddingCommand(
            from: .zero,
            to: PaddingConfig(top: 4, right: 4, bottom: 4, left: 4)
        )
        let second = SetPaddingCommand(
            from: PaddingConfig(top: 4, right: 4, bottom: 4, left: 4),
            to: PaddingConfig(top: 12, right: 12, bottom: 12, left: 12)
        )

        let merged = first.coalesce(with: second) as? SetPaddingCommand
        XCTAssertNotNil(merged)
        XCTAssertEqual(merged?.from, .zero)
        XCTAssertEqual(merged?.to, PaddingConfig(top: 12, right: 12, bottom: 12, left: 12))
    }

    func test_setPadding_coalesce_withDifferentCommand_returnsNil() {
        let padding = SetPaddingCommand(
            from: .zero,
            to: PaddingConfig(top: 4, right: 4, bottom: 4, left: 4)
        )
        let background = SetBackgroundCommand(
            from: .none,
            to: .solidColor(CGColor(red: 0, green: 0, blue: 0, alpha: 1))
        )

        XCTAssertNil(padding.coalesce(with: background))
    }

    func test_setBackground_applyThenRevert_isIdentity() {
        var doc = makeDoc()
        let before = doc.background
        let target = BackgroundStyle.solidColor(CGColor(red: 0.2, green: 0.4, blue: 0.6, alpha: 1))
        let command = SetBackgroundCommand(from: doc.background, to: target)

        command.apply(to: &doc)
        XCTAssertEqual(doc.background, target)
        command.revert(to: &doc)
        XCTAssertEqual(doc.background, before)
    }

    func test_setBackground_coalesce_keepsOriginalFrom() {
        let first = SetBackgroundCommand(from: .none, to: .solidColor(CGColor(gray: 0.2, alpha: 1)))
        let second = SetBackgroundCommand(
            from: .solidColor(CGColor(gray: 0.2, alpha: 1)),
            to: .dynamic
        )
        let merged = first.coalesce(with: second) as? SetBackgroundCommand
        XCTAssertNotNil(merged)
        XCTAssertEqual(merged?.from, BackgroundStyle.none)
        XCTAssertEqual(merged?.to, .dynamic)
    }

    func test_setPadding_applyAndRevert_neverMutatesAnnotations() {
        var doc = makeDoc()
        doc.annotations = [
            Annotation(kind: .text(
                origin: CGPoint(x: 6, y: 8),
                string: "Pinned",
                fontSize: 14,
                color: CGColor(gray: 0, alpha: 1)
            ))
        ]
        let annotations = doc.annotations
        let command = SetPaddingCommand(from: .zero, to: .uniform(24))

        command.apply(to: &doc)
        XCTAssertEqual(doc.annotations, annotations)
        command.revert(to: &doc)
        XCTAssertEqual(doc.annotations, annotations)
    }

    func test_applyAutoPadding_isOneUndoableActionThatDoesNotMutateAnnotations() {
        var doc = makeDoc()
        doc.annotations = [
            Annotation(kind: .text(
                origin: CGPoint(x: 6, y: 8),
                string: "Pinned",
                fontSize: 14,
                color: CGColor(gray: 0, alpha: 1)
            ))
        ]
        let beforePadding = doc.padding
        let beforeBackground = doc.background
        let beforeAnnotations = doc.annotations
        let stack = UndoStack()
        let command = ApplyAutoPaddingCommand(
            fromPadding: doc.padding,
            toPadding: .uniform(40),
            fromBackground: doc.background,
            toBackground: .defaultGradient
        )

        stack.push(command, apply: { $0.apply(to: &doc) })

        XCTAssertEqual(stack.undoCount, 1)
        XCTAssertEqual(doc.padding, .uniform(40))
        XCTAssertEqual(doc.background, .defaultGradient)
        XCTAssertEqual(doc.annotations, beforeAnnotations)

        stack.undo(revert: { $0.revert(to: &doc) })
        XCTAssertEqual(doc.padding, beforePadding)
        XCTAssertEqual(doc.background, beforeBackground)
        XCTAssertEqual(doc.annotations, beforeAnnotations)
    }
}
