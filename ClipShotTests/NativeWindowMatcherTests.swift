import CoreGraphics
import XCTest
@testable import ClipShot

final class NativeWindowMatcherTests: XCTestCase {

    func testScreencaptureRectArgumentRoundsGlobalPointRect() {
        let arg = NativeScreencaptureCLI.rectArgument(
            for: CGRect(x: 12.4, y: 80.6, width: 200.4, height: 100.2)
        )

        XCTAssertEqual(arg, "12,81,200,100")
    }

    func testWindowCornerRadiusRescalesIntoColorGrid() {
        let radius = NativeWindowShaping.cornerRadius(
            shapeRadius: 12,
            shapeSize: CGSize(width: 800, height: 500),
            colorSize: CGSize(width: 1600, height: 1000)
        )

        XCTAssertEqual(radius, 24)
    }

    func testWindowCornerRadiusUnchangedForEqualGrids() {
        let radius = NativeWindowShaping.cornerRadius(
            shapeRadius: 18,
            shapeSize: CGSize(width: 800, height: 500),
            colorSize: CGSize(width: 800, height: 500)
        )

        XCTAssertEqual(radius, 18)
    }

    func testWholeWindowSelectionMatchesWindow() {
        let window = CGRect(x: 100, y: 120, width: 800, height: 500)
        let region = window.insetBy(dx: -8, dy: -8)

        let match = NativeWindowMatcher.bestMatch(frames: [window], in: region)

        XCTAssertEqual(match?.index, 0)
        XCTAssertGreaterThanOrEqual(match?.windowCoverage ?? 0, 0.90)
        XCTAssertGreaterThanOrEqual(match?.regionCoverage ?? 0, 0.50)
    }

    func testSelectionInsideWindowDoesNotMatchWindow() {
        let window = CGRect(x: 100, y: 120, width: 800, height: 500)
        let region = CGRect(x: 240, y: 240, width: 260, height: 180)

        let match = NativeWindowMatcher.bestMatch(frames: [window], in: region)

        XCTAssertNil(match)
    }

    func testNearWindowBoundarySelectionMatchesWindow() {
        let window = CGRect(x: 100, y: 120, width: 800, height: 500)
        let region = window.insetBy(dx: 20, dy: 20)

        let match = NativeWindowMatcher.bestMatch(frames: [window], in: region)

        XCTAssertEqual(match?.index, 0)
        XCTAssertGreaterThanOrEqual(match?.windowCoverage ?? 0, 0.90)
        XCTAssertGreaterThanOrEqual(match?.regionCoverage ?? 0, 0.50)
    }

    func testLargeSelectionAroundWindowDoesNotMatchWhenWindowIsMinorityOfRegion() {
        let window = CGRect(x: 100, y: 120, width: 800, height: 500)
        let region = CGRect(x: 0, y: 0, width: 1800, height: 1200)

        let match = NativeWindowMatcher.bestMatch(frames: [window], in: region)

        XCTAssertNil(match)
    }

    func testBestMatchPrefersWindowWithMostOverlap() {
        let backgroundWindow = CGRect(x: 0, y: 0, width: 1400, height: 900)
        let leadingWindow = CGRect(x: 180, y: 140, width: 720, height: 460)
        let region = leadingWindow.insetBy(dx: -6, dy: -6)

        let match = NativeWindowMatcher.bestMatch(
            frames: [backgroundWindow, leadingWindow],
            in: region
        )

        XCTAssertEqual(match?.index, 1)
    }
}
