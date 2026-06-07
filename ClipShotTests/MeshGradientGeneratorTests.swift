import XCTest
@testable import ClipShot

final class MeshGradientGeneratorTests: XCTestCase {

    private let full = CGRect.null

    private func luminance(_ c: CGColor) -> CGFloat {
        let k = c.components!
        return 0.2126 * k[0] + 0.7152 * k[1] + 0.0722 * k[2]
    }
    private func meanLuminance(_ spec: MeshSpec) -> CGFloat {
        spec.colors.map(luminance).reduce(0, +) / CGFloat(spec.colors.count)
    }
    private func distinctCount(_ spec: MeshSpec) -> Int {
        var set = Set<String>()
        for c in spec.colors {
            let k = c.components!
            set.insert("\(Int((k[0] * 20).rounded()))-\(Int((k[1] * 20).rounded()))-\(Int((k[2] * 20).rounded()))")
        }
        return set.count
    }

    func test_generate_alwaysReturnsNineColors() {
        let img = FixtureDocument.makeSolidImage(
            color: CGColor(srgbRed: 0.2, green: 0.3, blue: 0.7, alpha: 1), size: CGSize(width: 90, height: 90))
        XCTAssertEqual(MeshGradientGenerator.generate(screenshot: img, selection: full).colors.count, 9)
    }

    func test_generate_monochromeInput_stillProducesVariedField() {
        // A near-monochrome blue image must NOT yield a flat field.
        let img = FixtureDocument.makeSolidImage(
            color: CGColor(srgbRed: 0.16, green: 0.30, blue: 0.62, alpha: 1), size: CGSize(width: 90, height: 90))
        let spec = MeshGradientGenerator.generate(screenshot: img, selection: full)
        let lums = spec.colors.map(luminance)
        let spread = lums.max()! - lums.min()!
        XCTAssertGreaterThan(spread, 0.08, "field must have directional luminance depth")
        XCTAssertGreaterThanOrEqual(distinctCount(spec), 3, "field must have multiple distinct colors")
    }

    func test_generate_brightImage_producesRecessiveDarkerField() {
        let img = FixtureDocument.makeSolidImage(
            color: CGColor(srgbRed: 0.88, green: 0.88, blue: 0.90, alpha: 1), size: CGSize(width: 60, height: 60))
        let spec = MeshGradientGenerator.generate(screenshot: img, selection: full)
        XCTAssertLessThan(meanLuminance(spec), 0.82, "bright card → dimmer background")
    }

    func test_generate_darkImage_producesLighterField() {
        let img = FixtureDocument.makeSolidImage(
            color: CGColor(srgbRed: 0.08, green: 0.09, blue: 0.13, alpha: 1), size: CGSize(width: 60, height: 60))
        let spec = MeshGradientGenerator.generate(screenshot: img, selection: full)
        XCTAssertGreaterThan(meanLuminance(spec), 0.16, "dark card → lighter background")
    }

    func test_generate_isDeterministic() {
        let img = FixtureDocument.makeQuadrantImage(
            tl: CGColor(srgbRed: 0.8, green: 0.1, blue: 0.1, alpha: 1),
            tr: CGColor(srgbRed: 0.1, green: 0.8, blue: 0.1, alpha: 1),
            bl: CGColor(srgbRed: 0.1, green: 0.1, blue: 0.8, alpha: 1),
            br: CGColor(srgbRed: 0.8, green: 0.8, blue: 0.1, alpha: 1), size: CGSize(width: 90, height: 90))
        let a = MeshGradientGenerator.generate(screenshot: img, selection: full)
        let b = MeshGradientGenerator.generate(screenshot: img, selection: full)
        XCTAssertEqual(a, b)
    }
}
