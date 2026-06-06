import CoreGraphics
import XCTest
@testable import ClipShot

final class NativeWindowMatcherTests: XCTestCase {

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
