import XCTest
@testable import ClipShot

final class MeshGradientGeneratorTests: XCTestCase {

    private let full = CGRect.null

    private func hsbSaturation(_ c: CGColor) -> CGFloat {
        let ns = NSColor(cgColor: c)!.usingColorSpace(.sRGB)!
        var h: CGFloat = 0, s: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        ns.getHue(&h, saturation: &s, brightness: &b, alpha: &a)
        return s
    }

    private func dominantChannel(_ c: CGColor) -> Int {
        let comps = c.components!
        let arr = [comps[0], comps[1], comps[2]]
        return arr.firstIndex(of: arr.max()!)!
    }

    func test_generate_alwaysReturnsNineColors() {
        let img = FixtureDocument.makeSolidImage(
            color: CGColor(srgbRed: 0.8, green: 0.1, blue: 0.1, alpha: 1),
            size: CGSize(width: 90, height: 90))
        XCTAssertEqual(MeshGradientGenerator.generate(screenshot: img, selection: full).colors.count, 9)
    }

    func test_generate_solidRed_allCellsAreRedDominant() {
        let img = FixtureDocument.makeSolidImage(
            color: CGColor(srgbRed: 0.8, green: 0.1, blue: 0.1, alpha: 1),
            size: CGSize(width: 90, height: 90))
        let spec = MeshGradientGenerator.generate(screenshot: img, selection: full)
        for c in spec.colors { XCTAssertEqual(dominantChannel(c), 0, "red channel should dominate") }
    }

    func test_generate_quadrants_cornerCellsMatchQuadrantHues() {
        let red = CGColor(srgbRed: 0.8, green: 0.1, blue: 0.1, alpha: 1)
        let green = CGColor(srgbRed: 0.1, green: 0.8, blue: 0.1, alpha: 1)
        let blue = CGColor(srgbRed: 0.1, green: 0.1, blue: 0.8, alpha: 1)
        let yellow = CGColor(srgbRed: 0.8, green: 0.8, blue: 0.1, alpha: 1)
        let img = FixtureDocument.makeQuadrantImage(
            tl: red, tr: green, bl: blue, br: yellow, size: CGSize(width: 90, height: 90))
        let spec = MeshGradientGenerator.generate(screenshot: img, selection: full)
        XCTAssertEqual(dominantChannel(spec.colors[0]), 0, "TL → red")
        XCTAssertEqual(dominantChannel(spec.colors[2]), 1, "TR → green")
        XCTAssertEqual(dominantChannel(spec.colors[6]), 2, "BL → blue")
        XCTAssertLessThan(spec.colors[8].components![2], spec.colors[8].components![0])
    }

    func test_generate_appliesSaturationFloor() {
        let grayish = CGColor(srgbRed: 0.5, green: 0.5, blue: 0.52, alpha: 1)
        let img = FixtureDocument.makeSolidImage(color: grayish, size: CGSize(width: 60, height: 60))
        let spec = MeshGradientGenerator.generate(screenshot: img, selection: full)
        for c in spec.colors {
            XCTAssertGreaterThanOrEqual(hsbSaturation(c), 0.15 - 0.001)
        }
    }

    func test_generate_isDeterministic() {
        let img = FixtureDocument.makeQuadrantImage(
            tl: CGColor(srgbRed: 0.8, green: 0.1, blue: 0.1, alpha: 1),
            tr: CGColor(srgbRed: 0.1, green: 0.8, blue: 0.1, alpha: 1),
            bl: CGColor(srgbRed: 0.1, green: 0.1, blue: 0.8, alpha: 1),
            br: CGColor(srgbRed: 0.8, green: 0.8, blue: 0.1, alpha: 1),
            size: CGSize(width: 90, height: 90))
        let a = MeshGradientGenerator.generate(screenshot: img, selection: full)
        let b = MeshGradientGenerator.generate(screenshot: img, selection: full)
        XCTAssertEqual(a, b)
    }
}
