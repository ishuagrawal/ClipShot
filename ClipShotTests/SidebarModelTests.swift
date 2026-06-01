import CoreGraphics
import XCTest
@testable import ClipShot

@MainActor
final class SidebarModelTests: XCTestCase {

    // MARK: PaddingConfig box model

    func testUniformBuildsEqualSides() {
        let padding = PaddingConfig.uniform(20)
        XCTAssertEqual(padding, PaddingConfig(top: 20, right: 20, bottom: 20, left: 20))
    }

    func testIsLinkedWhenAllSidesEqual() {
        XCTAssertTrue(PaddingConfig.uniform(12).isLinked)
        XCTAssertFalse(PaddingConfig(top: 12, right: 0, bottom: 12, left: 12).isLinked)
    }

    func testSettingChangesOnlyOneSide() {
        let padding = PaddingConfig.uniform(10).setting(.right, to: 40)
        XCTAssertEqual(padding, PaddingConfig(top: 10, right: 40, bottom: 10, left: 10))
    }

    func testClampedBoundsEachSide() {
        let padding = PaddingConfig(top: -5, right: 9999, bottom: 30, left: 0).clamped()
        XCTAssertEqual(padding, PaddingConfig(top: 0, right: 256, bottom: 30, left: 0))
    }

    // MARK: BackgroundStyle.Kind

    func testKindMapsEachCase() {
        XCTAssertEqual(BackgroundStyle.none.kind, .none)
        XCTAssertEqual(BackgroundStyle.solidColor(CGColor(gray: 0, alpha: 1)).kind, .solid)
        XCTAssertEqual(
            BackgroundStyle.gradient(
                start: CGColor(gray: 0, alpha: 1),
                end: CGColor(gray: 1, alpha: 1),
                angleDegrees: 90
            ).kind,
            .gradient
        )
        XCTAssertEqual(BackgroundStyle.blurExtend(radius: 10).kind, .blurExtend)
    }

    func testKindHasAllFourCases() {
        XCTAssertEqual(BackgroundStyle.Kind.allCases.count, 4)
    }

    // MARK: EditorState inspector model

    private func makeState() -> EditorState {
        EditorState(document: FixtureDocument.basicPair().document)
    }

    func testSelectCursorToolSetsActiveToolAndClearsPanel() {
        let state = makeState()
        state.toggleDocumentPanel(.layout)
        state.selectCursorTool(.arrow)
        XCTAssertEqual(state.activeTool, .arrow)
        XCTAssertEqual(state.documentPanel, .none)
    }

    func testToggleDocumentPanelTwiceReturnsToNone() {
        let state = makeState()
        state.toggleDocumentPanel(.layout)
        XCTAssertEqual(state.documentPanel, .layout)
        state.toggleDocumentPanel(.layout)
        XCTAssertEqual(state.documentPanel, .none)
    }

    func testOpeningDocumentPanelResetsCursorToSelect() {
        let state = makeState()
        state.selectCursorTool(.rectangle)
        state.toggleDocumentPanel(.background)
        XCTAssertEqual(state.activeTool, .select)
        XCTAssertEqual(state.documentPanel, .background)
    }

    func testInspectorHiddenWhenSelectIdleNoPanel() {
        let state = makeState()
        XCTAssertEqual(state.inspectorRoute, .hidden)
        XCTAssertFalse(state.isInspectorVisible)
    }

    func testInspectorRouteLayoutWhenPanelLayout() {
        let state = makeState()
        state.toggleDocumentPanel(.layout)
        XCTAssertEqual(state.inspectorRoute, .layout)
        XCTAssertEqual(state.inspectorTitle, "Layout")
    }

    func testInspectorRouteDrawDefaultsWhenDrawToolIdle() {
        let state = makeState()
        state.selectCursorTool(.arrow)
        XCTAssertEqual(state.inspectorRoute, .drawDefaults(.arrow))
        XCTAssertEqual(state.inspectorTitle, "Arrow")
    }

    func testInspectorRouteAnnotationWhenSelected() {
        let state = makeState()
        state.selectCursorTool(.arrow)
        state.beginDraw(at: CGPoint(x: 10, y: 10))
        state.updateDraw(to: CGPoint(x: 90, y: 90), shiftSnap: false)
        _ = state.commitDraw()
        XCTAssertNotNil(state.selectedAnnotationID)
        XCTAssertEqual(state.inspectorRoute, .annotation)
        XCTAssertEqual(state.inspectorTitle, "Arrow")
    }

    func testDismissInspectorClearsEverything() {
        let state = makeState()
        state.toggleDocumentPanel(.layout)
        state.dismissInspector()
        XCTAssertEqual(state.documentPanel, .none)
        XCTAssertEqual(state.activeTool, .select)
        XCTAssertNil(state.selectedAnnotationID)
        XCTAssertEqual(state.inspectorRoute, .hidden)
    }

    func testOpeningPanelInitSeedsLayout() {
        let state = EditorState(
            document: FixtureDocument.basicPair().document,
            openingPanel: .layout
        )
        XCTAssertEqual(state.inspectorRoute, .layout)
        XCTAssertTrue(state.isInspectorVisible)
    }

    func testDisabledDrawToolIsIgnored() {
        let state = makeState()
        state.selectCursorTool(.blur)
        XCTAssertEqual(state.activeTool, .select)
    }
}
