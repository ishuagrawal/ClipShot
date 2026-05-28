import XCTest
@testable import ClipShot

final class SanityTest: XCTestCase {
    func test_pixelBuffer_decodesSolidColorPNG() throws {
        // Synthesize a 4x4 red PNG.
        let width = 4
        let height = 4
        let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
        let ctx = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
                | CGBitmapInfo.byteOrder32Big.rawValue
        )!
        ctx.setFillColor(red: 1, green: 0, blue: 0, alpha: 1)
        ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
        let cgImage = ctx.makeImage()!
        let png = NSBitmapImageRep(cgImage: cgImage).representation(using: .png, properties: [:])!

        let buffer = try XCTUnwrap(PixelBuffer.decode(png))
        XCTAssertEqual(buffer.width, 4)
        XCTAssertEqual(buffer.height, 4)
        // First pixel RGBA: red, green=0, blue=0, alpha=255.
        XCTAssertEqual(buffer.pixels[0], 255)
        XCTAssertEqual(buffer.pixels[1], 0)
        XCTAssertEqual(buffer.pixels[2], 0)
        XCTAssertEqual(buffer.pixels[3], 255)
    }
}
