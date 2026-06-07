import CoreGraphics

/// Pure, deterministic extraction of a 3×3 mesh-color grid from a screenshot.
/// Gathers the image's prominent colors, places each near where it appears
/// (spatial), then dims/desaturates the field so the screenshot card stays the
/// most vivid, in-focus element — an Apple-Music-style backdrop, not a seamless
/// extension of the image.
enum MeshGradientGenerator {

    private static let sampleSize = 100
    private static let maxPaletteColors = 5
    private static let distinctThreshold = 0.15
    private static let contrastGap = 0.22
    private static let desaturation = 0.88   // 1 = none, lower = greyer

    static func generate(screenshot: CGImage, selection: CGRect) -> MeshSpec {
        guard let small = downscaled(screenshot, selection: selection),
              let pixels = pixelBytes(small), small.width >= 3, small.height >= 3 else {
            return fallbackSpec()
        }
        let w = small.width, h = small.height
        let colorsPalette = palette(in: pixels, width: w, height: h)
        guard !colorsPalette.isEmpty else { return fallbackSpec() }

        var colors: [CGColor] = []
        for row in 0..<3 {
            for col in 0..<3 {
                colors.append(blend(palette: colorsPalette, x: Double(col) / 2, y: Double(row) / 2))
            }
        }
        let cardL = averageLuminance(in: pixels, width: w, height: h)
        return MeshSpec(colors: applyContrast(colors, cardLuminance: cardL))
    }

    // MARK: - Palette with spatial centroids

    private struct PaletteColor {
        let r, g, b: Double
        let cx, cy: Double      // normalized centroid, y from visual top
        let count: Int
        let key: Int
    }

    private static func palette(in pixels: [UInt8], width w: Int, height h: Int) -> [PaletteColor] {
        var count = [Int: Int]()
        var sumR = [Int: Double](), sumG = [Int: Double](), sumB = [Int: Double]()
        var sumX = [Int: Double](), sumY = [Int: Double]()
        let denomX = Double(max(1, w - 1)), denomY = Double(max(1, h - 1))
        for y in 0..<h {
            let ny = Double(y) / denomY      // buffer row 0 == visual top
            for x in 0..<w {
                let i = (y * w + x) * 4
                let r = Double(pixels[i]) / 255
                let g = Double(pixels[i + 1]) / 255
                let b = Double(pixels[i + 2]) / 255
                let key = (Int(r * 15) << 8) | (Int(g * 15) << 4) | Int(b * 15)
                count[key, default: 0] += 1
                sumR[key, default: 0] += r
                sumG[key, default: 0] += g
                sumB[key, default: 0] += b
                sumX[key, default: 0] += Double(x) / denomX
                sumY[key, default: 0] += ny
            }
        }
        let total = Double(w * h)
        let minCount = max(1, Int(total * 0.005))    // ignore <0.5% specks
        var candidates: [PaletteColor] = []
        for (k, c) in count where c >= minCount {
            let n = Double(c)
            candidates.append(PaletteColor(
                r: sumR[k]! / n, g: sumG[k]! / n, b: sumB[k]! / n,
                cx: sumX[k]! / n, cy: sumY[k]! / n, count: c, key: k))
        }
        if candidates.isEmpty {       // everything was specks → take the single most common
            if let best = count.max(by: { $0.value != $1.value ? $0.value < $1.value : $0.key < $1.key }) {
                let k = best.key, n = Double(best.value)
                candidates.append(PaletteColor(
                    r: sumR[k]! / n, g: sumG[k]! / n, b: sumB[k]! / n,
                    cx: sumX[k]! / n, cy: sumY[k]! / n, count: best.value, key: k))
            }
        }
        // Prominent AND vivid first; deterministic tie-break by key.
        candidates.sort {
            let s0 = score($0), s1 = score($1)
            return s0 != s1 ? s0 > s1 : $0.key > $1.key
        }
        var chosen: [PaletteColor] = []
        for cand in candidates {
            if chosen.count >= maxPaletteColors { break }
            if chosen.allSatisfy({ colorDistance($0, cand) > distinctThreshold }) {
                chosen.append(cand)
            }
        }
        return chosen
    }

    private static func score(_ c: PaletteColor) -> Double {
        let sat = Double(saturation(CGFloat(c.r), CGFloat(c.g), CGFloat(c.b)))
        return Double(c.count) * (0.35 + 0.65 * sat)
    }

    private static func colorDistance(_ a: PaletteColor, _ b: PaletteColor) -> Double {
        let dr = a.r - b.r, dg = a.g - b.g, db = a.b - b.b
        return (dr * dr + dg * dg + db * db).squareRoot()
    }

    // MARK: - Spatial inverse-distance blend

    private static func blend(palette: [PaletteColor], x px: Double, y py: Double) -> CGColor {
        var wr = 0.0, wg = 0.0, wb = 0.0, wsum = 0.0
        for p in palette {
            let dx = px - p.cx, dy = py - p.cy
            let weight = 1.0 / (dx * dx + dy * dy + 0.03)
            wr += p.r * weight; wg += p.g * weight; wb += p.b * weight; wsum += weight
        }
        guard wsum > 0 else { return CGColor(srgbRed: 0.5, green: 0.5, blue: 0.5, alpha: 1) }
        return CGColor(srgbRed: wr / wsum, green: wg / wsum, blue: wb / wsum, alpha: 1)
    }

    // MARK: - Adaptive contrast

    private static func applyContrast(_ colors: [CGColor], cardLuminance cardL: Double) -> [CGColor] {
        let targetMean = cardL >= 0.5 ? max(0.08, cardL - contrastGap)
                                      : min(0.92, cardL + contrastGap)
        let mean = max(0.001, colors.map(lum).reduce(0, +) / Double(colors.count))
        let factor = targetMean / mean
        return colors.map { c in
            let comps = c.components ?? [0, 0, 0, 1]
            var r = min(1, max(0, Double(comps[0]) * factor))
            var g = min(1, max(0, Double(comps[1]) * factor))
            var b = min(1, max(0, Double(comps[2]) * factor))
            let grey = 0.2126 * r + 0.7152 * g + 0.0722 * b
            r = r * desaturation + grey * (1 - desaturation)
            g = g * desaturation + grey * (1 - desaturation)
            b = b * desaturation + grey * (1 - desaturation)
            return CGColor(srgbRed: r, green: g, blue: b, alpha: 1)
        }
    }

    private static func lum(_ c: CGColor) -> Double {
        let comps = c.components ?? [0, 0, 0, 1]
        return 0.2126 * Double(comps[0]) + 0.7152 * Double(comps[1]) + 0.0722 * Double(comps[2])
    }

    private static func averageLuminance(in pixels: [UInt8], width w: Int, height h: Int) -> Double {
        var sum = 0.0
        let n = w * h
        for p in 0..<n {
            let i = p * 4
            sum += 0.2126 * Double(pixels[i]) + 0.7152 * Double(pixels[i + 1]) + 0.0722 * Double(pixels[i + 2])
        }
        return sum / (Double(n) * 255)
    }

    // MARK: - Downscale / pixels

    private static func downscaled(_ image: CGImage, selection: CGRect) -> CGImage? {
        let crop = selection.integral.intersection(
            CGRect(x: 0, y: 0, width: image.width, height: image.height))
        let source = (crop.isNull || crop.isEmpty) ? image : (image.cropping(to: crop) ?? image)
        let longSide = max(source.width, source.height)
        guard longSide > 0 else { return nil }
        let scale = min(1.0, Double(sampleSize) / Double(longSide))
        let w = max(3, Int(Double(source.width) * scale))
        let h = max(3, Int(Double(source.height) * scale))
        let ctx = CGContext(
            data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        ctx?.interpolationQuality = .medium
        ctx?.draw(source, in: CGRect(x: 0, y: 0, width: w, height: h))
        return ctx?.makeImage()
    }

    private static func pixelBytes(_ image: CGImage) -> [UInt8]? {
        let w = image.width, h = image.height
        var data = [UInt8](repeating: 0, count: w * h * 4)
        let ctx = data.withUnsafeMutableBytes { ptr -> CGContext? in
            CGContext(
                data: ptr.baseAddress, width: w, height: h, bitsPerComponent: 8,
                bytesPerRow: w * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        }
        guard let ctx else { return nil }
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        return data
    }

    private static func saturation(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat) -> CGFloat {
        let maxC = max(r, g, b), minC = min(r, g, b)
        return maxC <= 0 ? 0 : (maxC - minC) / maxC
    }

    private static func fallbackSpec() -> MeshSpec {
        let s = BackgroundStyle.defaultGradientStart
        let e = BackgroundStyle.defaultGradientEnd
        return MeshSpec(colors: [s, s, mid(s, e), s, mid(s, e), e, mid(s, e), e, e])
    }

    private static func mid(_ a: CGColor, _ b: CGColor) -> CGColor {
        let ca = a.components ?? [0, 0, 0, 1], cb = b.components ?? [0, 0, 0, 1]
        return CGColor(srgbRed: (ca[0] + cb[0]) / 2, green: (ca[1] + cb[1]) / 2,
                       blue: (ca[2] + cb[2]) / 2, alpha: 1)
    }
}
