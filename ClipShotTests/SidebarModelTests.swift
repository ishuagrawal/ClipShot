import XCTest
@testable import ClipShot

@MainActor
final class SidebarModelTests: XCTestCase {

    // MARK: EditorTool.hasDetailPanel

    func testSelectHasNoDetailPanel() {
        XCTAssertFalse(EditorTool.select.hasDetailPanel)
    }

    func testOtherToolsHaveDetailPanel() {
        for tool in EditorTool.allCases where tool != .select {
            XCTAssertTrue(tool.hasDetailPanel, "\(tool) should have a detail panel")
        }
    }

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

    // MARK: EditorState panel state

    private func makeState() -> EditorState {
        EditorState(document: FixtureDocument.basicPair().document)
    }

    func testSelectingPanelToolExpandsPanel() {
        let state = makeState()
        state.isDetailPanelExpanded = false
        state.selectTool(.padding)
        XCTAssertEqual(state.activeTool, .padding)
        XCTAssertTrue(state.isDetailPanelExpanded)
        XCTAssertTrue(state.isDetailPanelVisible)
    }

    func testReselectingActiveToolTogglesPanel() {
        let state = makeState()
        state.selectTool(.padding)
        state.selectTool(.padding)
        XCTAssertFalse(state.isDetailPanelExpanded)
        XCTAssertFalse(state.isDetailPanelVisible)
    }

    func testSelectToolHasNoVisiblePanel() {
        let state = makeState()
        state.selectTool(.padding)
        state.selectTool(.select)
        XCTAssertEqual(state.activeTool, .select)
        XCTAssertFalse(state.isDetailPanelVisible)
    }

    func testDisabledToolIsIgnored() {
        let state = makeState()
        state.selectTool(.arrow)
        XCTAssertEqual(state.activeTool, .select)
    }

    func testToggleDetailPanelFlipsExpansion() {
        let state = makeState()
        state.selectTool(.background)
        state.toggleDetailPanel()
        XCTAssertFalse(state.isDetailPanelExpanded)
        state.toggleDetailPanel()
        XCTAssertTrue(state.isDetailPanelExpanded)
    }
}
