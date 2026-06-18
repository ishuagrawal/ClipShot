import CoreGraphics
import Foundation
import Vision

/// The detected content region plus the background color to synthesize whitespace with.
struct ContentBounds: Equatable {
    let box: CGRect       // imagePx, offset into the analyzed image
    let fillColor: CGColor
}

/// Finds the content bounding box inside a screenshot region by trimming a uniform
/// background (the `-trim` technique). Pure: CGImage + rect in. Falls back to Vision
/// saliency when no uniform background is present.
struct ContentBoundsDetector {
    var channelThreshold: Int = 12     // per-channel diff from background to count as content
    var minContentPixels: Int = 2      // content pixels a row/col needs to count (ignores stray noise)
    var cornerTolerance: Int = 24      // max channel spread among bg samples to call them uniform
    var backgroundUniformFraction: Double = 0.7  // share of border samples that must match to call it a bg
    var minSize: CGFloat = 8
    var minSaliencyConfidence: Float = 0.1

    /// Content bounds in imagePx, or nil when no confident content region exists —
    /// no uniform background and no salient object.
    func detect(in image: CGImage, region: CGRect) -> ContentBounds? {
        let imageBounds = CGRect(x: 0, y: 0, width: image.width, height: image.height)
        let r = region.integral.intersection(imageBounds)
        guard r.width >= minSize, r.height >= minSize,
              let cropped = image.cropping(to: r),
              let buffer = RGBABuffer(cropped) else { return nil }

        if let background = backgroundColor(buffer),
           let local = trimBox(buffer, background: background) {
            let box = CGRect(
                x: r.minX + CGFloat(local.minX),
                y: r.minY + CGFloat(local.minY),
                width: CGFloat(local.width),
                height: CGFloat(local.height)
            )
            guard let clamped = clamp(box, to: imageBounds) else { return nil }
            return ContentBounds(box: clamped, fillColor: cgColor(background))
        }

        guard let box = saliencyBox(cropped, region: r, imageBounds: imageBounds) else { return nil }
        let fill = borderColor(of: box, in: image) ?? cgColor((255, 255, 255))
        return ContentBounds(box: box, fillColor: fill)
    }

    // MARK: - Background estimate

    private func backgroundColor(_ buffer: RGBABuffer) -> (Int, Int, Int)? {
        let samples = borderSamples(buffer)
        guard !samples.isEmpty else { return nil }
        let median = medianColor(samples)
        // Fraction, not all-or-nothing: a thin frame where content touches a few
        // border points stays a valid background instead of dropping to saliency.
        let within = samples.filter { channelDiff($0, median) <= cornerTolerance }.count
        return Double(within) / Double(samples.count) >= backgroundUniformFraction ? median : nil
    }

    /// Dense border ring — samples along all four edges, off the very edge. Never the
    /// center, which centered content would occupy and falsely read as non-uniform.
    private func borderSamples(_ buffer: RGBABuffer) -> [(Int, Int, Int)] {
        let w = buffer.width, h = buffer.height
        let inset = max(1, min(w, h) / 100)
        let step = max(1, min(w, h) / 64)
        let lastX = w - 1 - inset, lastY = h - 1 - inset
        var samples: [(Int, Int, Int)] = []
        for x in stride(from: 0, to: w, by: step) {
            samples.append(buffer.rgb(x: x, y: inset))
            samples.append(buffer.rgb(x: x, y: lastY))
        }
        for y in stride(from: 0, to: h, by: step) {
            samples.append(buffer.rgb(x: inset, y: y))
            samples.append(buffer.rgb(x: lastX, y: y))
        }
        return samples
    }

    private func medianColor(_ samples: [(Int, Int, Int)]) -> (Int, Int, Int) {
        let mid = samples.count / 2
        return (
            samples.map(\.0).sorted()[mid],
            samples.map(\.1).sorted()[mid],
            samples.map(\.2).sorted()[mid]
        )
    }

    /// Median color around a box's border, used as the inset fill when no uniform
    /// region background was found (the salient object's own edge color).
    private func borderColor(of box: CGRect, in image: CGImage) -> CGColor? {
        guard let cropped = image.cropping(to: box.integral), let buffer = RGBABuffer(cropped) else { return nil }
        let samples = borderSamples(buffer)
        guard !samples.isEmpty else { return nil }
        return cgColor(medianColor(samples))
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

    private func cgColor(_ rgb: (Int, Int, Int)) -> CGColor {
        CGColor(srgbRed: CGFloat(rgb.0) / 255, green: CGFloat(rgb.1) / 255, blue: CGFloat(rgb.2) / 255, alpha: 1)
    }

    private func clamp(_ box: CGRect, to bounds: CGRect) -> CGRect? {
        let clamped = box.integral.intersection(bounds)
        guard clamped.width >= minSize, clamped.height >= minSize else { return nil }
        return clamped
    }
}

/// Builds a new card image: the content region surrounded by an equal band of a
/// fill color, synthesizing whitespace inside the screenshot itself.
enum ContentInsetComposer {
    static func compose(screenshot: CGImage, content: CGRect, inset: CGFloat, fill: CGColor) -> CGImage? {
        let box = content.integral
        let pad = max(0, inset.rounded())
        let width = Int(box.width + 2 * pad)
        let height = Int(box.height + 2 * pad)
        guard width > 0, height > 0,
              let contentImage = screenshot.cropping(to: box) else { return nil }

        let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
        guard let ctx = CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8,
            bytesPerRow: width * 4, space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
                | CGBitmapInfo.byteOrder32Big.rawValue
        ) else { return nil }

        ctx.setFillColor(fill)
        ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
        // Equal inset all around → the content sits centered in the y-up context.
        ctx.draw(contentImage, in: CGRect(x: pad, y: pad, width: box.width, height: box.height))
        return ctx.makeImage()
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
