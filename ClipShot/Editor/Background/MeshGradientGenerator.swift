import AppKit
import CoreGraphics

/// Pure, deterministic extraction of a 3×3 mesh-color grid from a screenshot,
/// so the padding around the card visually continues the image at every edge.
enum MeshGradientGenerator {

    private static let sampleSize = 100          // long-side downscale target
    private static let minSaturation: CGFloat = 0.15
    private static let saturationBoost: CGFloat = 1.12

    static func generate(screenshot: CGImage, selection: CGRect) -> MeshSpec {
        guard let small = downscaled(screenshot, selection: selection) else {
            return fallbackSpec()
        }
        let w = small.width, h = small.height
        guard let pixels = pixelBytes(small), w >= 3, h >= 3 else { return fallbackSpec() }

        var colors: [CGColor] = []
        for row in 0..<3 {
            for col in 0..<3 {
                let rect = cellRect(col: col, row: row, width: w, height: h)
                let c = dominantColor(in: pixels, width: w, rect: rect)
                colors.append(vivid(c))
            }
        }
        return MeshSpec(colors: colors)
    }

    private static func downscaled(_ image: CGImage, selection: CGRect) -> CGImage? {
        let crop = selection.integral.intersection(
            CGRect(x: 0, y: 0, width: image.width, height: image.height)
        )
        let source = (crop.isNull || crop.isEmpty) ? image : (image.cropping(to: crop) ?? image)
        let longSide = max(source.width, source.height)
        guard longSide > 0 else { return nil }
        let scale = min(1.0, Double(sampleSize) / Double(longSide))
        let w = max(3, Int(Double(source.width) * scale))
        let h = max(3, Int(Double(source.height) * scale))
        let ctx = CGContext(
            data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )
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
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            )
        }
        guard let ctx else { return nil }
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        return data
    }

    /// grid row 0 = TOP of the image.
    /// When a CGImage is drawn into a CGContext bitmap and the bytes are read back,
    /// the CGImage's visual row 0 (top) maps to buffer y=0 — CGContext draw() flips
    /// the image relative to the context's own bottom-left convention. So grid row 0
    /// maps directly to buffer y=0 with NO flip needed.
    private static func cellRect(col: Int, row: Int, width w: Int, height h: Int) -> CGRect {
        let cw = w / 3, ch = h / 3
        let x = col * cw
        let y = row * ch
        return CGRect(x: x, y: y, width: cw, height: ch)
    }

    private static func dominantColor(in pixels: [UInt8], width w: Int, rect: CGRect) -> CGColor {
        var counts: [Int: Int] = [:]
        var satCounts: [Int: Int] = [:]
        var repColor: [Int: (CGFloat, CGFloat, CGFloat)] = [:]
        let x0 = Int(rect.minX), y0 = Int(rect.minY)
        let x1 = Int(rect.maxX), y1 = Int(rect.maxY)
        for y in y0..<y1 {
            for x in x0..<x1 {
                let i = (y * w + x) * 4
                let r = CGFloat(pixels[i + 0]) / 255
                let g = CGFloat(pixels[i + 1]) / 255
                let b = CGFloat(pixels[i + 2]) / 255
                let key = (Int(r * 31) << 10) | (Int(g * 31) << 5) | Int(b * 31)
                counts[key, default: 0] += 1
                repColor[key] = (r, g, b)
                if saturation(r, g, b) >= minSaturation { satCounts[key, default: 0] += 1 }
            }
        }
        // Tie-break by key to ensure determinism despite Swift's hash randomization.
        let pick = satCounts.max(by: { $0.value != $1.value ? $0.value < $1.value : $0.key < $1.key })?.key
            ?? counts.max(by: { $0.value != $1.value ? $0.value < $1.value : $0.key < $1.key })?.key
        guard let key = pick, let c = repColor[key] else {
            return CGColor(srgbRed: 0.5, green: 0.5, blue: 0.5, alpha: 1)
        }
        return CGColor(srgbRed: c.0, green: c.1, blue: c.2, alpha: 1)
    }

    private static func vivid(_ color: CGColor) -> CGColor {
        let ns = NSColor(cgColor: color) ?? .gray
        guard let rgb = ns.usingColorSpace(.sRGB) else { return color }
        var hue: CGFloat = 0, sat: CGFloat = 0, bri: CGFloat = 0, alpha: CGFloat = 0
        rgb.getHue(&hue, saturation: &sat, brightness: &bri, alpha: &alpha)
        sat = min(1, max(minSaturation, sat) * saturationBoost)
        bri = min(1, max(0.25, bri))
        return NSColor(hue: hue, saturation: sat, brightness: bri, alpha: 1).cgColor
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
        let ca = a.components ?? [0,0,0,1], cb = b.components ?? [0,0,0,1]
        return CGColor(srgbRed: (ca[0]+cb[0])/2, green: (ca[1]+cb[1])/2,
                       blue: (ca[2]+cb[2])/2, alpha: 1)
    }
}
