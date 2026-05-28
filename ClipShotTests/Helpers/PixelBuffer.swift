import AppKit
import CoreGraphics
import Foundation

/// Decode a PNG (or any CGImage) into a deterministic RGBA8 premultiplied sRGB byte buffer.
/// Use this for equality comparisons — PNG file bytes are encoder-dependent and unreliable.
enum PixelBuffer {
    struct Buffer: Equatable {
        let width: Int
        let height: Int
        let bytesPerRow: Int
        let pixels: Data
    }

    static func decode(_ pngData: Data) -> Buffer? {
        guard let rep = NSBitmapImageRep(data: pngData),
              let cgImage = rep.cgImage else { return nil }
        return decode(cgImage)
    }

    static func decode(_ cgImage: CGImage) -> Buffer? {
        let width = cgImage.width
        let height = cgImage.height
        let bytesPerRow = width * 4
        var pixels = Data(count: bytesPerRow * height)
        let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
        let bitmapInfo: UInt32 =
            CGImageAlphaInfo.premultipliedLast.rawValue
            | CGBitmapInfo.byteOrder32Big.rawValue
        let ok = pixels.withUnsafeMutableBytes { raw -> Bool in
            guard let base = raw.baseAddress,
                  let ctx = CGContext(
                    data: base,
                    width: width,
                    height: height,
                    bitsPerComponent: 8,
                    bytesPerRow: bytesPerRow,
                    space: colorSpace,
                    bitmapInfo: bitmapInfo
                  )
            else { return false }
            ctx.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard ok else { return nil }
        return Buffer(width: width, height: height, bytesPerRow: bytesPerRow, pixels: pixels)
    }
}
