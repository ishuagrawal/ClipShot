import XCTest
@testable import ClipShot

final class CommandTests: XCTestCase {

    private func makeDoc() -> EditorDocument {
        EditorDocument(
            screenshot: TestImage.solid(.red, size: CGSize(width: 100, height: 100)),
            viewport: CGSize(width: 100, height: 100),
            pageTitle: "t",
            pageURL: "u",
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
        let first = SetBackgroundCommand(from: .none, to: .blurExtend(radius: 10))
        let second = SetBackgroundCommand(from: .blurExtend(radius: 10), to: .blurExtend(radius: 30))

        let merged = first.coalesce(with: second) as? SetBackgroundCommand
        XCTAssertNotNil(merged)
        XCTAssertEqual(merged?.from, BackgroundStyle.none)
        XCTAssertEqual(merged?.to, .blurExtend(radius: 30))
    }
}
