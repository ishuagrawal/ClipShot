import XCTest
@testable import ClipShot

final class MeshGradientGeneratorTests: XCTestCase {

    private let full = CGRect.null

    private func dominantChannel(_ c: CGColor) -> Int {
        let comps = c.components!
        let arr = [comps[0], comps[1], comps[2]]
        return arr.firstIndex(of: arr.max()!)!
    }

    private func luminance(_ c: CGColor) -> CGFloat {
        let k = c.components!
        return 0.2126 * k[0] + 0.7152 * k[1] + 0.0722 * k[2]
    }

    private func meanLuminance(_ spec: MeshSpec) -> CGFloat {
        spec.colors.map(luminance).reduce(0, +) / CGFloat(spec.colors.count)
    }

    func test_generate_alwaysReturnsNineColors() {
        let img = FixtureDocument.makeSolidImage(
            color: CGColor(srgbRed: 0.5, green: 0.2, blue: 0.2, alpha: 1),
            size: CGSize(width: 90, height: 90))
        XCTAssertEqual(MeshGradientGenerator.generate(screenshot: img, selection: full).colors.count, 9)
    }

    func test_generate_solidColor_keepsHueDominant() {
        let img = FixtureDocument.makeSolidImage(
            color: CGColor(srgbRed: 0.6, green: 0.15, blue: 0.15, alpha: 1),
            size: CGSize(width: 90, height: 90))
        let spec = MeshGradientGenerator.generate(screenshot: img, selection: full)
        for c in spec.colors { XCTAssertEqual(dominantChannel(c), 0, "red stays dominant hue") }
    }

    func test_generate_spatial_cornersFollowImageLayout() {
        let red = CGColor(srgbRed: 0.8, green: 0.1, blue: 0.1, alpha: 1)
        let green = CGColor(srgbRed: 0.1, green: 0.8, blue: 0.1, alpha: 1)
        let blue = CGColor(srgbRed: 0.1, green: 0.1, blue: 0.8, alpha: 1)
        let yellow = CGColor(srgbRed: 0.8, green: 0.8, blue: 0.1, alpha: 1)
        let img = FixtureDocument.makeQuadrantImage(
            tl: red, tr: green, bl: blue, br: yellow, size: CGSize(width: 90, height: 90))
        let spec = MeshGradientGenerator.generate(screenshot: img, selection: full)
        XCTAssertEqual(dominantChannel(spec.colors[0]), 0, "TL leans red")
        XCTAssertEqual(dominantChannel(spec.colors[2]), 1, "TR leans green")
        XCTAssertEqual(dominantChannel(spec.colors[6]), 2, "BL leans blue")
    }

    func test_generate_brightImage_producesDarkerField() {
        let img = FixtureDocument.makeSolidImage(
            color: CGColor(srgbRed: 0.85, green: 0.85, blue: 0.85, alpha: 1),
            size: CGSize(width: 60, height: 60))
        let spec = MeshGradientGenerator.generate(screenshot: img, selection: full)
        XCTAssertLessThan(meanLuminance(spec), 0.72, "bright card → dimmer background")
    }

    func test_generate_darkImage_producesLighterField() {
        let img = FixtureDocument.makeSolidImage(
            color: CGColor(srgbRed: 0.10, green: 0.10, blue: 0.12, alpha: 1),
            size: CGSize(width: 60, height: 60))
        let spec = MeshGradientGenerator.generate(screenshot: img, selection: full)
        XCTAssertGreaterThan(meanLuminance(spec), 0.20, "dark card → lighter background")
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
