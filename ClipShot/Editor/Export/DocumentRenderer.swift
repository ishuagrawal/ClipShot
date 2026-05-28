import CoreGraphics
import Foundation

/// Pure, deterministic flattener. Identical pipeline for canvas preview and Copy/Save.
///
/// Operates entirely in PIXEL SPACE: the bitmap dimensions equal
/// `doc.effectiveCrop.integral.size` and NO scale factor is applied to the context
/// (the browser extension already absorbed devicePixelRatio when capturing).
///
/// Document coordinate space is y-down (top-left origin) to match the CSS / extension
/// convention that future annotation/text drawing (P2) will rely on.
///
/// P0 implements crop-only (no padding visuals, no background, no annotations).
enum DocumentRenderer {

    static func render(_ doc: EditorDocument) -> CGImage? {
        let cropPx = doc.effectiveCrop.integral
        let width = Int(cropPx.width)
        let height = Int(cropPx.height)
        guard width > 0, height > 0 else { return nil }

        let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
        guard let ctx = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
                | CGBitmapInfo.byteOrder32Big.rawValue
        ) else { return nil }

        // Establish y-down (top-left origin) document space for future annotation drawing.
        ctx.translateBy(x: 0, y: CGFloat(height))
        ctx.scaleBy(x: 1, y: -1)

        // P0: background is .none (transparent) — nothing to fill.

        // Draw the screenshot crop. dest is in documentPt (top-left origin).
        let dest = CGRect(
            x: doc.padding.left,
            y: doc.padding.top,
            width: doc.baseSelection.width,
            height: doc.baseSelection.height
        )
        if let cropped = doc.screenshot.cropping(to: doc.baseSelection.integral) {
            // CGContextDrawImage renders upside-down in a y-flipped context. Locally
            // re-flip around the destination rect so the screenshot stays upright.
            ctx.saveGState()
            ctx.translateBy(x: dest.minX, y: dest.maxY)
            ctx.scaleBy(x: 1, y: -1)
            ctx.draw(cropped, in: CGRect(origin: .zero, size: dest.size))
            ctx.restoreGState()
        }

        // P0: no annotations.

        return ctx.makeImage()
    }
}
