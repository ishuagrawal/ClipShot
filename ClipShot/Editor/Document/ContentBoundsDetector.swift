import CoreGraphics
import Foundation
import Vision

/// Finds the content bounding box inside a screenshot region by trimming a uniform
/// background (the `-trim` technique). Pure: CGImage + rect in, rect out. Falls back
/// to Vision saliency when no uniform background is present.
struct ContentBoundsDetector {
    var channelThreshold: Int = 12     // per-channel diff from background to count as content
    var minContentPixels: Int = 2      // content pixels a row/col needs to count (ignores stray noise)
    var cornerTolerance: Int = 24      // max channel spread among bg samples to call them uniform
    var minSize: CGFloat = 8
    var minSaliencyConfidence: Float = 0.1

    /// Content bbox in imagePx (offset into `image`), or nil when no confident
    /// content region exists — no uniform background and no salient object.
    func detect(in image: CGImage, region: CGRect) -> CGRect? {
        let imageBounds = CGRect(x: 0, y: 0, width: image.width, height: image.height)
        let r = region.integral.intersection(imageBounds)
        guard r.width >= minSize, r.height >= minSize,
              let cropped = image.cropping(to: r),
              let buffer = RGBABuffer(cropped) else { return nil }

        guard let background = backgroundColor(buffer),
              let local = trimBox(buffer, background: background) else {
            return saliencyBox(cropped, region: r, imageBounds: imageBounds)
        }

        let box = CGRect(
            x: r.minX + CGFloat(local.minX),
            y: r.minY + CGFloat(local.minY),
            width: CGFloat(local.width),
            height: CGFloat(local.height)
        )
        return clamp(box, to: imageBounds)
    }

    // MARK: - Background estimate

    private func backgroundColor(_ buffer: RGBABuffer) -> (Int, Int, Int)? {
        let w = buffer.width, h = buffer.height
        let inset = max(1, min(w, h) / 50)
        let lastX = w - 1 - inset, lastY = h - 1 - inset
        // Border ring only — corners + edge midpoints. Never the center, which
        // centered content would occupy and falsely read as non-uniform.
        let points = [
            (inset, inset), (lastX, inset), (inset, lastY), (lastX, lastY),
            (w / 2, inset), (w / 2, lastY), (inset, h / 2), (lastX, h / 2)
        ]
        let samples = points
            .filter { $0.0 >= 0 && $0.0 < w && $0.1 >= 0 && $0.1 < h }
            .map { buffer.rgb(x: $0.0, y: $0.1) }
        guard !samples.isEmpty else { return nil }

        let median = (
            samples.map(\.0).sorted()[samples.count / 2],
            samples.map(\.1).sorted()[samples.count / 2],
            samples.map(\.2).sorted()[samples.count / 2]
        )
        let uniform = samples.allSatisfy { channelDiff($0, median) <= cornerTolerance }
        return uniform ? median : nil
    }

    // MARK: - Trim scan

    private func trimBox(_ buffer: RGBABuffer, background: (Int, Int, Int)) -> (minX: Int, minY: Int, width: Int, height: Int)? {
        let w = buffer.width, h = buffer.height
        var rowCount = [Int](repeating: 0, count: h)
        var colCount = [Int](repeating: 0, count: w)
        for y in 0..<h {
            for x in 0..<w where channelDiff(buffer.rgb(x: x, y: y), background) > channelThreshold {
                rowCount[y] += 1
                colCount[x] += 1
            }
        }
        guard let minY = rowCount.firstIndex(where: { $0 >= minContentPixels }),
              let maxY = rowCount.lastIndex(where: { $0 >= minContentPixels }),
              let minX = colCount.firstIndex(where: { $0 >= minContentPixels }),
              let maxX = colCount.lastIndex(where: { $0 >= minContentPixels }) else { return nil }
        return (minX, minY, maxX - minX + 1, maxY - minY + 1)
    }

    // MARK: - Saliency fallback

    private func saliencyBox(_ image: CGImage, region: CGRect, imageBounds: CGRect) -> CGRect? {
        let request = VNGenerateAttentionBasedSaliencyImageRequest()
        let handler = VNImageRequestHandler(cgImage: image, options: [:])
        guard (try? handler.perform([request])) != nil,
              let observation = request.results?.first as? VNSaliencyImageObservation,
              let object = observation.salientObjects?.max(by: { $0.confidence < $1.confidence }),
              object.confidence >= minSaliencyConfidence else { return nil }

        // Vision boundingBox is normalized with a bottom-left origin; flip y to top-left.
        let bb = object.boundingBox
        let box = CGRect(
            x: region.minX + bb.minX * region.width,
            y: region.minY + (1 - bb.maxY) * region.height,
            width: bb.width * region.width,
            height: bb.height * region.height
        )
        guard let clamped = clamp(box, to: imageBounds) else { return nil }
        return clamped == region.integral ? nil : clamped
    }

    // MARK: - Helpers

    private func channelDiff(_ a: (Int, Int, Int), _ b: (Int, Int, Int)) -> Int {
        max(abs(a.0 - b.0), abs(a.1 - b.1), abs(a.2 - b.2))
    }

    private func clamp(_ box: CGRect, to bounds: CGRect) -> CGRect? {
        let clamped = box.integral.intersection(bounds)
        guard clamped.width >= minSize, clamped.height >= minSize else { return nil }
        return clamped
    }
}

/// Tightly packed RGBA8 premultiplied sRGB pixels for synchronous CPU reads.
private struct RGBABuffer {
    let width: Int
    let height: Int
    let bytesPerRow: Int
    let pixels: [UInt8]

    init?(_ image: CGImage) {
        let width = image.width
        let height = image.height
        guard width > 0, height > 0 else { return nil }
        let bytesPerRow = width * 4
        var pixels = [UInt8](repeating: 0, count: bytesPerRow * height)
        let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
        let ok = pixels.withUnsafeMutableBytes { raw -> Bool in
            guard let base = raw.baseAddress,
                  let ctx = CGContext(
                    data: base,
                    width: width,
                    height: height,
                    bitsPerComponent: 8,
                    bytesPerRow: bytesPerRow,
                    space: colorSpace,
                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
                        | CGBitmapInfo.byteOrder32Big.rawValue
                  ) else { return false }
            ctx.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard ok else { return nil }
        self.width = width
        self.height = height
        self.bytesPerRow = bytesPerRow
        self.pixels = pixels
    }

    func rgb(x: Int, y: Int) -> (Int, Int, Int) {
        let offset = y * bytesPerRow + x * 4
        return (Int(pixels[offset]), Int(pixels[offset + 1]), Int(pixels[offset + 2]))
    }
}
