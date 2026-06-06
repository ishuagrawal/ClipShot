import CoreGraphics

/// A row-major 3×3 grid of colors describing a smooth mesh gradient.
/// Index 0 = top-left, 4 = center, 8 = bottom-right.
struct MeshSpec: Equatable {
    let colors: [CGColor]   // count == 9

    /// Bilinear-interpolated bitmap of the grid at the requested pixel size,
    /// with a small ordered dither to suppress 8-bit banding.
    func render(size: CGSize) -> CGImage? {
        let w = max(1, Int(size.width.rounded()))
        let h = max(1, Int(size.height.rounded()))
        guard colors.count == 9 else { return nil }

        let space = CGColorSpace(name: CGColorSpace.sRGB)!
        guard let ctx = CGContext(
            data: nil, width: w, height: h, bitsPerComponent: 8,
            bytesPerRow: w * 4, space: space,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
                | CGBitmapInfo.byteOrder32Big.rawValue
        ), let buffer = ctx.data else { return nil }

        let rgba = buffer.bindMemory(to: UInt8.self, capacity: w * h * 4)
        let grid = colors.map { Self.rgb($0) }

        for y in 0..<h {
            let fy = h == 1 ? 0 : Double(y) / Double(h - 1)
            for x in 0..<w {
                let fx = w == 1 ? 0 : Double(x) / Double(w - 1)
                let c = Self.sample(grid: grid, fx: fx, fy: fy)
                let dither = Self.dither(x: x, y: y)
                let i = (y * w + x) * 4
                rgba[i + 0] = Self.byte(c.0 + dither)
                rgba[i + 1] = Self.byte(c.1 + dither)
                rgba[i + 2] = Self.byte(c.2 + dither)
                rgba[i + 3] = 255
            }
        }
        return ctx.makeImage()
    }

    private static func sample(grid: [(Double, Double, Double)], fx: Double, fy: Double)
        -> (Double, Double, Double) {
        let gx = fx * 2, gy = fy * 2
        let x0 = min(1, Int(gx)), y0 = min(1, Int(gy))
        let tx = gx - Double(x0), ty = gy - Double(y0)
        func at(_ cx: Int, _ cy: Int) -> (Double, Double, Double) { grid[cy * 3 + cx] }
        let top = lerp(at(x0, y0), at(x0 + 1, y0), tx)
        let bot = lerp(at(x0, y0 + 1), at(x0 + 1, y0 + 1), tx)
        return lerp(top, bot, ty)
    }

    private static func lerp(_ a: (Double, Double, Double), _ b: (Double, Double, Double), _ t: Double)
        -> (Double, Double, Double) {
        (a.0 + (b.0 - a.0) * t, a.1 + (b.1 - a.1) * t, a.2 + (b.2 - a.2) * t)
    }

    private static func dither(x: Int, y: Int) -> Double {
        let m: [[Double]] = [
            [0, 8, 2, 10], [12, 4, 14, 6], [3, 11, 1, 9], [15, 7, 13, 5]
        ]
        return (m[y & 3][x & 3] / 16.0 - 0.5) / 255.0
    }

    private static func byte(_ v: Double) -> UInt8 {
        UInt8(max(0, min(255, (v * 255).rounded())))
    }

    private static func rgb(_ c: CGColor) -> (Double, Double, Double) {
        let space = CGColorSpace(name: CGColorSpace.sRGB)!
        let conv = c.converted(to: space, intent: .defaultIntent, options: nil) ?? c
        let comps = conv.components ?? [0, 0, 0, 1]
        if comps.count >= 3 { return (Double(comps[0]), Double(comps[1]), Double(comps[2])) }
        let g = Double(comps.first ?? 0); return (g, g, g)
    }
}
