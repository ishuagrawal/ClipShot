import XCTest
@testable import ClipShot

final class UndoStackTests: XCTestCase {

    /// A throwaway command that adds a known integer key to an `Annotation` array.
    /// Lets us observe the document state without depending on real concrete commands.
    private struct AppendTagCommand: EditorCommand {
        let tag: Int
        var displayName: String { "Append \(tag)" }

        func apply(to document: inout EditorDocument) {
            document.annotations.append(
                Annotation(kind: .rect(
                    frame: CGRect(x: CGFloat(tag), y: 0, width: 1, height: 1),
                    stroke: nil, fill: nil, weight: 0, cornerRadius: 0))
            )
        }

        func revert(to document: inout EditorDocument) {
            document.annotations.removeLast()
        }

        func coalesce(with next: EditorCommand) -> EditorCommand? { nil }
    }

    private func makeDoc() -> EditorDocument {
        EditorDocument(
            screenshot: TestImage.solid(.red, size: CGSize(width: 100, height: 100)),
            viewport: CGSize(width: 100, height: 100),
            pageTitle: "t", pageURL: "u",
            baseSelection: CGRect(x: 0, y: 0, width: 50, height: 50)
        )
    }

    func test_push_appliesCommandAndExposesUndoButNotRedo() {
        var doc = makeDoc()
        let stack = UndoStack()
        stack.push(AppendTagCommand(tag: 1), apply: { $0.apply(to: &doc) })
        XCTAssertEqual(doc.annotations.count, 1)
        XCTAssertTrue(stack.canUndo)
        XCTAssertFalse(stack.canRedo)
    }

    func test_undo_revertsLastCommandAndMovesItToRedo() {
        var doc = makeDoc()
        let stack = UndoStack()
        stack.push(AppendTagCommand(tag: 1), apply: { $0.apply(to: &doc) })
        stack.undo(revert: { $0.revert(to: &doc) })
        XCTAssertEqual(doc.annotations.count, 0)
        XCTAssertFalse(stack.canUndo)
        XCTAssertTrue(stack.canRedo)
    }

    func test_redo_replaysCommand() {
        var doc = makeDoc()
        let stack = UndoStack()
        stack.push(AppendTagCommand(tag: 1), apply: { $0.apply(to: &doc) })
        stack.undo(revert: { $0.revert(to: &doc) })
        stack.redo(apply: { $0.apply(to: &doc) })
        XCTAssertEqual(doc.annotations.count, 1)
        XCTAssertTrue(stack.canUndo)
        XCTAssertFalse(stack.canRedo)
    }

    func test_newPush_clearsRedoStack() {
        var doc = makeDoc()
        let stack = UndoStack()
        stack.push(AppendTagCommand(tag: 1), apply: { $0.apply(to: &doc) })
        stack.undo(revert: { $0.revert(to: &doc) })
        XCTAssertTrue(stack.canRedo)
        stack.push(AppendTagCommand(tag: 2), apply: { $0.apply(to: &doc) })
        XCTAssertFalse(stack.canRedo)
    }

    func test_stack_capsAtOneHundredEntries() {
        var doc = makeDoc()
        let stack = UndoStack()
        for tag in 0..<150 {
            stack.push(AppendTagCommand(tag: tag), apply: { $0.apply(to: &doc) })
        }
        XCTAssertEqual(stack.undoCount, 100)
    }

    func test_undoOnEmpty_isNoOp() {
        var doc = makeDoc()
        let stack = UndoStack()
        let before = doc
        stack.undo(revert: { $0.revert(to: &doc) })
        XCTAssertEqual(doc, before)
    }

    func test_coalesce_mergesWithinWindow() {
        struct PadCommand: EditorCommand {
            let from: CGFloat
            let to: CGFloat
            var displayName: String { "Pad \(to)" }
            func apply(to document: inout EditorDocument) {
                document.padding = PaddingConfig(top: to, right: to, bottom: to, left: to)
            }
            func revert(to document: inout EditorDocument) {
                document.padding = PaddingConfig(top: from, right: from, bottom: from, left: from)
            }
            func coalesce(with next: EditorCommand) -> EditorCommand? {
                guard let next = next as? PadCommand else { return nil }
                return PadCommand(from: from, to: next.to)
            }
        }

        var doc = makeDoc()
        let stack = UndoStack(coalesceWindow: 0.5, clock: TestClock())
        let clock = stack.clock as! TestClock

        clock.now = 0.0
        stack.push(PadCommand(from: 0, to: 10), apply: { $0.apply(to: &doc) })
        clock.now = 0.2
        stack.push(PadCommand(from: 10, to: 20), apply: { $0.apply(to: &doc) })
        XCTAssertEqual(stack.undoCount, 1)
        XCTAssertEqual(doc.padding.uniform, 20)

        clock.now = 0.9
        stack.push(PadCommand(from: 20, to: 30), apply: { $0.apply(to: &doc) })
        XCTAssertEqual(stack.undoCount, 2)
    }
}

/// Mutable clock injected for deterministic time-window tests.
final class TestClock: Clock {
    var now: TimeInterval = 0
    func currentTime() -> TimeInterval { now }
}
