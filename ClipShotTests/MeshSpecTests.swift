import XCTest
@testable import ClipShot

final class MeshSpecTests: XCTestCase {

    private func red() -> CGColor { CGColor(srgbRed: 1, green: 0, blue: 0, alpha: 1) }

    func test_render_returnsRequestedSize() throws {
        let spec = MeshSpec(colors: Array(repeating: red(), count: 9))
        let img = try XCTUnwrap(spec.render(size: CGSize(width: 20, height: 12)))
        XCTAssertEqual(img.width, 20)
        XCTAssertEqual(img.height, 12)
    }

    func test_render_solidGrid_isUniformColor() throws {
        let spec = MeshSpec(colors: Array(repeating: red(), count: 9))
        let img = try XCTUnwrap(spec.render(size: CGSize(width: 16, height: 16)))
        let buf = try XCTUnwrap(PixelBuffer.decode(img))
        let i = (8 * buf.bytesPerRow) + 8 * 4
        XCTAssertEqual(Int(buf.pixels[i + 0]), 255, accuracy: 2)
        XCTAssertLessThanOrEqual(Int(buf.pixels[i + 1]), 2)
        XCTAssertLessThanOrEqual(Int(buf.pixels[i + 2]), 2)
    }

    func test_render_horizontalGradient_leftDiffersFromRight() throws {
        let r = red(), b = CGColor(srgbRed: 0, green: 0, blue: 1, alpha: 1)
        let spec = MeshSpec(colors: [r, r.midpoint(b), b, r, r.midpoint(b), b, r, r.midpoint(b), b])
        let img = try XCTUnwrap(spec.render(size: CGSize(width: 32, height: 8)))
        let buf = try XCTUnwrap(PixelBuffer.decode(img))
        let row = 4 * buf.bytesPerRow
        let left = Int(buf.pixels[row + 0])
        let right = Int(buf.pixels[row + (31 * 4) + 2])
        XCTAssertGreaterThan(left, 200)
        XCTAssertGreaterThan(right, 200)
    }
}

private extension CGColor {
    func midpoint(_ other: CGColor) -> CGColor {
        let a = components ?? [0,0,0,1], b = other.components ?? [0,0,0,1]
        return CGColor(srgbRed: (a[0]+b[0])/2, green: (a[1]+b[1])/2, blue: (a[2]+b[2])/2, alpha: 1)
    }
}
