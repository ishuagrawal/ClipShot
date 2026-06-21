import CoreGraphics
import Foundation

struct BackgroundPaletteRequest: Equatable {
    let ref: WallpaperRef
    let aspect: CGFloat
    let key: String

    init?(background: BackgroundStyle, effectiveCrop: CGRect) {
        guard case .image(let ref) = background else { return nil }
        self.ref = ref
        self.aspect = effectiveCrop.height > 0 ? effectiveCrop.width / effectiveCrop.height : 1
        self.key = "img:\(ref.key)#\(String(format: "%.6f", Double(aspect)))"
    }

    func matches(background: BackgroundStyle, effectiveCrop: CGRect, currentKey: String) -> Bool {
        guard currentKey == key,
              let current = BackgroundPaletteRequest(
                background: background,
                effectiveCrop: effectiveCrop
              ) else {
            return false
        }
        return current == self
    }
}

/// Samples an image's literal colors at 9 anchor points in mesh order (index
/// 0 = top-left, 2 = top-right, 8 = bottom-right). Each anchor matches where
/// `AmbientGlowView` places its blob (corners at 0/1, edge mids at 0.5), and is
/// read as a small patch around that point — so a corner blob gets the real
/// corner color, not a third-of-the-image average that smears a steep gradient.
/// No harmonizing or reordering: blue stays on the blue side. The source is
/// cropped aspect-fill to the card so sampled edges match what's on screen.
enum EdgePaletteSampler {
    /// Normalized anchor points (u,v), v top-down, in mesh order.
    private static let anchors: [(u: Double, v: Double)] = [
        (0, 0), (0.5, 0), (1, 0),
        (0, 0.5), (0.5, 0.5), (1, 0.5),
        (0, 1), (0.5, 1), (1, 1)
    ]
    /// Half-size of the sampled patch, as a fraction of each axis.
    private static let patchHalf = 0.06

    static func grid(from image: CGImage, cardAspect: CGFloat) -> [CGColor] {
        let src = aspectFillCrop(image, aspect: cardAspect)
        let w = max(3, min(160, src.width))
        let h = max(3, min(160, src.height))
        var data = [UInt8](repeating: 0, count: w * h * 4)
        let ctx = data.withUnsafeMutableBytes { ptr -> CGContext? in
            CGContext(data: ptr.baseAddress, width: w, height: h, bitsPerComponent: 8,
                      bytesPerRow: w * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        }
        guard let ctx else { return [] }
        ctx.draw(src, in: CGRect(x: 0, y: 0, width: w, height: h))

        let hw = max(1, Int((patchHalf * Double(w)).rounded()))
        let hh = max(1, Int((patchHalf * Double(h)).rounded()))
        return anchors.map { anchor in
            let cx = Int((anchor.u * Double(w - 1)).rounded())
            // ctx.draw stores buffer row 0 at the image top, so v maps directly.
            let cy = Int((anchor.v * Double(h - 1)).rounded())
            let x0 = max(0, cx - hw), x1 = min(w, cx + hw + 1)
            let y0 = max(0, cy - hh), y1 = min(h, cy + hh + 1)
            return average(data, w: w, x0: x0, x1: x1, y0: y0, y1: y1)
        }
    }

    /// Center crop to the card's aspect (W/H), mirroring the on-screen aspect-fill.
    private static func aspectFillCrop(_ image: CGImage, aspect: CGFloat) -> CGImage {
        let iw = Double(image.width), ih = Double(image.height)
        guard iw > 0, ih > 0, aspect > 0 else { return image }
        let imgAspect = iw / ih
        var cw = iw, ch = ih
        if imgAspect > Double(aspect) { cw = ih * Double(aspect) } else { ch = iw / Double(aspect) }
        let rect = CGRect(x: (iw - cw) / 2, y: (ih - ch) / 2, width: cw, height: ch).integral
        return image.cropping(to: rect) ?? image
    }

    private static func average(_ d: [UInt8], w: Int,
                                x0: Int, x1: Int, y0: Int, y1: Int) -> CGColor {
        var r = 0.0, g = 0.0, b = 0.0, n = 0.0
        for y in y0..<max(y0 + 1, y1) {
            for x in x0..<max(x0 + 1, x1) {
                let i = (y * w + x) * 4
                let a = Double(d[i + 3])
                guard a > 0 else { continue }
                r += Double(d[i]) / a
                g += Double(d[i + 1]) / a
                b += Double(d[i + 2]) / a
                n += 1
            }
        }
        guard n > 0 else { return CGColor(srgbRed: 0, green: 0, blue: 0, alpha: 1) }
        // Return the true patch color. Tight anchor patches aren't muddy, so no
        // saturation hack — the glow should equal the artboard's actual colors.
        return CGColor(srgbRed: r / n, green: g / n, blue: b / n, alpha: 1)
    }
}
