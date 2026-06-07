import Foundation
import CoreGraphics

/// Pure, deterministic generation of a 3×3 mesh-color grid from a screenshot.
/// Expands the image's dominant color into a harmonized palette (analogous
/// shifts + one accent + tint + shade), lays it out directionally (light→dark
/// diagonal with an accent bloom), blends in OKLab for smooth vivid gradients,
/// then dims/desaturates so the screenshot card stays the in-focus element.
enum MeshGradientGenerator {

    private static let sampleSize = 100
    private static let analogShiftDeg = 32.0
    private static let accentShiftDeg = 72.0
    private static let contrastGap = 0.13        // OKLab L units
    private static let chromaScale = 0.82         // recessive desaturation
    private static let minChroma = 0.05
    private static let maxChroma = 0.22

    static func generate(screenshot: CGImage, selection: CGRect) -> MeshSpec {
        guard let small = downscaled(screenshot, selection: selection),
              let pixels = pixelBytes(small), small.width >= 3, small.height >= 3 else {
            return fallbackSpec()
        }
        let w = small.width, h = small.height
        let pal = palette(in: pixels, width: w, height: h)
        guard let dominant = pal.first else { return fallbackSpec() }
        let secondary = pal.count > 1 ? pal[1] : nil

        guard let avg = averageColor(in: pixels, width: w, height: h) else {
            return fallbackSpec()
        }
        let cardL = oklab(linearFromSRGB(avg)).0

        let anchors = anchors(dominant: dominant, secondary: secondary)
        var grid = layout(anchors)                      // 9 LCh
        grid = applyContrast(grid, cardL: cardL)
        return MeshSpec(colors: grid.map { srgb(fromLCh: $0) })
    }

    // MARK: - Harmonized anchors

    private struct LCh { var L: Double; var C: Double; var h: Double }   // h in radians

    private struct Anchors {
        var tint, analog1, base, analog2, shade, accent: LCh
    }

    private static func anchors(dominant: PaletteColor, secondary: PaletteColor?) -> Anchors {
        let d = lch(fromSRGB: (dominant.r, dominant.g, dominant.b))
        let baseC = min(maxChroma, max(minChroma, d.C * 1.15))
        let h = d.h
        func mk(_ L: Double, _ C: Double, _ degOffset: Double) -> LCh {
            LCh(L: clampL(L), C: clampC(C), h: h + degOffset * .pi / 180)
        }
        let base = LCh(L: clampL(d.L), C: baseC, h: h)
        let analog1 = mk(d.L + 0.06, baseC * 0.95, -analogShiftDeg)
        let analog2 = mk(d.L - 0.06, baseC * 1.05, analogShiftDeg)
        let tint = mk(d.L + 0.20, baseC * 0.65, -analogShiftDeg * 0.4)
        let shade = mk(d.L - 0.20, baseC * 1.10, analogShiftDeg * 0.5)
        let accent: LCh
        if let s = secondary {
            let a = lch(fromSRGB: (s.r, s.g, s.b))
            accent = LCh(L: clampL(a.L), C: clampC(max(baseC, a.C) * 1.2), h: a.h)
        } else {
            accent = mk(d.L, baseC * 1.30, accentShiftDeg)
        }
        return Anchors(tint: tint, analog1: analog1, base: base,
                       analog2: analog2, shade: shade, accent: accent)
    }

    /// Directional 3×3 layout: light tint top-left → deep shade bottom-right
    /// (diagonal depth), analogous sweep across the top, accent bloom bottom-left.
    private static func layout(_ a: Anchors) -> [LCh] {
        let tl = a.tint, tr = a.analog1, bl = a.accent, br = a.shade, c = a.base
        return [
            tl,                       // 0 TL
            blend(tl, tr, 0.5),       // 1 T
            tr,                       // 2 TR
            blend(tl, bl, 0.5),       // 3 L
            c,                        // 4 center
            blend(tr, br, 0.5),       // 5 R
            bl,                       // 6 BL
            blend(bl, br, 0.5),       // 7 B
            br                        // 8 BR
        ]
    }

    /// Perceptual blend through OKLab (lerp L,a,b), back to LCh.
    private static func blend(_ x: LCh, _ y: LCh, _ t: Double) -> LCh {
        let (lx, ax, bx) = labFromLCh(x)
        let (ly, ay, by) = labFromLCh(y)
        return lchFromLab(lx + (ly - lx) * t, ax + (ay - ax) * t, bx + (by - bx) * t)
    }

    // MARK: - Adaptive contrast

    private static func applyContrast(_ grid: [LCh], cardL: Double) -> [LCh] {
        let target = cardL >= 0.60 ? max(0.12, cardL - contrastGap)
                                   : min(0.92, cardL + contrastGap)
        let mean = grid.map(\.L).reduce(0, +) / Double(grid.count)
        let dL = target - mean
        return grid.map { LCh(L: clampL($0.L + dL), C: clampC($0.C * chromaScale), h: $0.h) }
    }

    private static func clampL(_ v: Double) -> Double { max(0.10, min(0.95, v)) }
    private static func clampC(_ v: Double) -> Double { max(0, min(maxChroma, v)) }

    // MARK: - Palette extraction (dominant + optional distinct secondary)

    struct PaletteColor { let r, g, b: Double; let weight: Double; let key: Int }

    private static func palette(in pixels: [UInt8], width w: Int, height h: Int) -> [PaletteColor] {
        var weight = [Int: Double]()
        var sumR = [Int: Double](), sumG = [Int: Double](), sumB = [Int: Double]()
        var totalWeight = 0.0
        for y in 0..<h {
            for x in 0..<w {
                let i = (y * w + x) * 4
                guard let sample = visibleSample(in: pixels, at: i) else { continue }
                let (r, g, b, alpha) = sample
                let key = (Int(r * 15) << 8) | (Int(g * 15) << 4) | Int(b * 15)
                weight[key, default: 0] += alpha
                sumR[key, default: 0] += r * alpha
                sumG[key, default: 0] += g * alpha
                sumB[key, default: 0] += b * alpha
                totalWeight += alpha
            }
        }
        let minimumWeight = totalWeight * 0.005
        var cands: [PaletteColor] = []
        for (key, value) in weight where value >= minimumWeight {
            cands.append(PaletteColor(
                r: sumR[key]! / value,
                g: sumG[key]! / value,
                b: sumB[key]! / value,
                weight: value,
                key: key
            ))
        }
        if cands.isEmpty, let best = weight.max(by: { $0.value != $1.value ? $0.value < $1.value : $0.key < $1.key }) {
            let key = best.key
            cands.append(PaletteColor(
                r: sumR[key]! / best.value,
                g: sumG[key]! / best.value,
                b: sumB[key]! / best.value,
                weight: best.value,
                key: key
            ))
        }
        cands.sort {
            let s0 = score($0), s1 = score($1)
            return s0 != s1 ? s0 > s1 : $0.key > $1.key
        }
        var chosen: [PaletteColor] = []
        for cand in cands {
            if chosen.count >= 4 { break }
            if chosen.allSatisfy({ colorDistance($0, cand) > 0.15 }) { chosen.append(cand) }
        }
        return chosen
    }

    private static func score(_ c: PaletteColor) -> Double {
        let maxC = max(c.r, c.g, c.b), minC = min(c.r, c.g, c.b)
        let sat = maxC <= 0 ? 0 : (maxC - minC) / maxC
        return c.weight * (0.35 + 0.65 * sat)
    }

    private static func colorDistance(_ a: PaletteColor, _ b: PaletteColor) -> Double {
        let dr = a.r - b.r, dg = a.g - b.g, db = a.b - b.b
        return (dr * dr + dg * dg + db * db).squareRoot()
    }

    private static func averageColor(
        in pixels: [UInt8],
        width w: Int,
        height h: Int
    ) -> (Double, Double, Double)? {
        var r = 0.0, g = 0.0, b = 0.0, totalWeight = 0.0
        for p in 0..<(w * h) {
            let i = p * 4
            guard let sample = visibleSample(in: pixels, at: i) else { continue }
            r += sample.r * sample.alpha
            g += sample.g * sample.alpha
            b += sample.b * sample.alpha
            totalWeight += sample.alpha
        }
        guard totalWeight > 0 else { return nil }
        return (r / totalWeight, g / totalWeight, b / totalWeight)
    }

    /// Pixel buffers are premultiplied RGBA. Ignore effectively transparent
    /// pixels, then un-premultiply visible colors before extracting the palette.
    private static func visibleSample(
        in pixels: [UInt8],
        at index: Int
    ) -> (r: Double, g: Double, b: Double, alpha: Double)? {
        let alphaByte = pixels[index + 3]
        guard alphaByte > 8 else { return nil }
        let divisor = Double(alphaByte)
        return (
            min(1, Double(pixels[index]) / divisor),
            min(1, Double(pixels[index + 1]) / divisor),
            min(1, Double(pixels[index + 2]) / divisor),
            divisor / 255
        )
    }

    // MARK: - OKLab / OKLCh color math (Björn Ottosson)

    private static func linearFromSRGB(_ c: (Double, Double, Double)) -> (Double, Double, Double) {
        func f(_ v: Double) -> Double { v <= 0.04045 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4) }
        return (f(c.0), f(c.1), f(c.2))
    }
    private static func srgbFromLinear(_ c: (Double, Double, Double)) -> (Double, Double, Double) {
        func g(_ v: Double) -> Double {
            let x = max(0, min(1, v))
            return x <= 0.0031308 ? 12.92 * x : 1.055 * pow(x, 1 / 2.4) - 0.055
        }
        return (g(c.0), g(c.1), g(c.2))
    }
    private static func oklab(_ lin: (Double, Double, Double)) -> (Double, Double, Double) {
        let (r, g, b) = lin
        let l = 0.4122214708 * r + 0.5363325363 * g + 0.0514459929 * b
        let m = 0.2119034982 * r + 0.6806995451 * g + 0.1073969566 * b
        let s = 0.0883024619 * r + 0.2817188376 * g + 0.6299787005 * b
        let l_ = cbrt(l), m_ = cbrt(m), s_ = cbrt(s)
        return (0.2104542553 * l_ + 0.7936177850 * m_ - 0.0040720468 * s_,
                1.9779984951 * l_ - 2.4285922050 * m_ + 0.4505937099 * s_,
                0.0259040371 * l_ + 0.7827717662 * m_ - 0.8086757660 * s_)
    }
    private static func linearFromOKLab(_ lab: (Double, Double, Double)) -> (Double, Double, Double) {
        let (L, a, b) = lab
        let l_ = L + 0.3963377774 * a + 0.2158037573 * b
        let m_ = L - 0.1055613458 * a - 0.0638541728 * b
        let s_ = L - 0.0894841775 * a - 1.2914855480 * b
        let l = l_ * l_ * l_, m = m_ * m_ * m_, s = s_ * s_ * s_
        return (4.0767416621 * l - 3.3077115913 * m + 0.2309699292 * s,
                -1.2684380046 * l + 2.6097574011 * m - 0.3413193965 * s,
                -0.0041960863 * l - 0.7034186147 * m + 1.7076147010 * s)
    }

    private static func labFromLCh(_ c: LCh) -> (Double, Double, Double) {
        (c.L, c.C * cos(c.h), c.C * sin(c.h))
    }
    private static func lchFromLab(_ L: Double, _ a: Double, _ b: Double) -> LCh {
        LCh(L: L, C: (a * a + b * b).squareRoot(), h: atan2(b, a))
    }
    private static func lch(fromSRGB c: (Double, Double, Double)) -> LCh {
        let (L, a, b) = oklab(linearFromSRGB(c))
        return lchFromLab(L, a, b)
    }
    private static func srgb(fromLCh c: LCh) -> CGColor {
        let (L, a, b) = labFromLCh(c)
        let (r, g, bb) = srgbFromLinear(linearFromOKLab((L, a, b)))
        return CGColor(srgbRed: r, green: g, blue: bb, alpha: 1)
    }

    // MARK: - Downscale / pixels

    private static func downscaled(_ image: CGImage, selection: CGRect) -> CGImage? {
        let crop = selection.integral.intersection(CGRect(x: 0, y: 0, width: image.width, height: image.height))
        let source = (crop.isNull || crop.isEmpty) ? image : (image.cropping(to: crop) ?? image)
        let longSide = max(source.width, source.height)
        guard longSide > 0 else { return nil }
        let scale = min(1.0, Double(sampleSize) / Double(longSide))
        let w = max(3, Int(Double(source.width) * scale))
        let h = max(3, Int(Double(source.height) * scale))
        let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
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
            CGContext(data: ptr.baseAddress, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                      space: CGColorSpace(name: CGColorSpace.sRGB)!,
                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        }
        guard let ctx else { return nil }
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        return data
    }

    private static func fallbackSpec() -> MeshSpec {
        let s = BackgroundStyle.defaultGradientStart
        let e = BackgroundStyle.defaultGradientEnd
        return MeshSpec(colors: [s, s, mid(s, e), s, mid(s, e), e, mid(s, e), e, e])
    }
    private static func mid(_ a: CGColor, _ b: CGColor) -> CGColor {
        let ca = a.components ?? [0, 0, 0, 1], cb = b.components ?? [0, 0, 0, 1]
        return CGColor(srgbRed: (ca[0] + cb[0]) / 2, green: (ca[1] + cb[1]) / 2, blue: (ca[2] + cb[2]) / 2, alpha: 1)
    }
}
