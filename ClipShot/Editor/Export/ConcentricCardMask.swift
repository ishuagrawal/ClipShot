import CoreGraphics
import CoreImage
import QuartzCore

/// The concentric padding-card coverage: the screenshot's drawn silhouette
/// (its real rounded/squircle corners) offset OUTWARD by the uniform padding
/// distance via a disc dilation (Minkowski sum). This is the true parallel
/// curve, so the gap between the screenshot corner and the card corner is
/// constant — exactly concentric for any corner radius or curve. Returns nil
/// when there is no rounded card to build (no corner radius, no padding, or
/// non-uniform padding, which falls back to the bezier path).
enum ConcentricCardMask {
    /// `clip` is a DeviceGray luminance mask for `CGContext.clip(to:mask:)`.
    /// `alpha` is a premultiplied white image carrying the coverage in its
    /// alpha channel, for use as a `CALayer.mask`'s contents.
    struct Coverage { let clip: CGImage; let alpha: CGImage }

    static func coverage(for doc: EditorDocument) -> Coverage? {
        Cache.shared.coverage(for: doc)
    }

    fileprivate static func build(for doc: EditorDocument) -> Coverage? {
        guard !doc.contentCornerRadii.isZero,
              let pad = doc.padding.uniform, pad > 0 else { return nil }

        let cardSize = doc.effectiveCrop.integral.size
        let cardW = Int(cardSize.width), cardH = Int(cardSize.height)
        guard cardW > 0, cardH > 0 else { return nil }

        // Work at a capped resolution so live dilation stays cheap; the mask is
        // smooth, so upscaling it for the clip/preview is visually invisible.
        let maxDim = 2200
        let scale = min(1.0, CGFloat(maxDim) / CGFloat(max(cardW, cardH)))
        let w = max(1, Int((CGFloat(cardW) * scale).rounded()))
        let h = max(1, Int((CGFloat(cardH) * scale).rounded()))

        guard let silhouette = drawnSilhouette(doc: doc, width: w, height: h, scale: scale) else { return nil }

        let dilated = CIImage(cgImage: silhouette)
            .clampedToExtent()
            .applyingFilter("CIMorphologyMaximum", parameters: [kCIInputRadiusKey: pad * scale])
        let rect = CGRect(x: 0, y: 0, width: w, height: h)
        // `CGContext.clip(to:mask:)` needs a DeviceGray luminance mask — render the
        // dilated coverage as L8 gray, not RGBA, or the clip is ignored.
        guard let clip = ciContext.createCGImage(
                dilated, from: rect, format: .L8, colorSpace: CGColorSpaceCreateDeviceGray()),
              let alpha = alphaImage(from: clip, width: w, height: h) else { return nil }
        return Coverage(clip: clip, alpha: alpha)
    }

    /// White-on-black Device-RGB(opaque-gray) image of the screenshot's drawn
    /// alpha: rounded by `selectionCornerRadii` for DOM captures, or the baked
    /// transparent corners for native window captures. Positioned inside the
    /// card exactly where the renderer draws the screenshot.
    private static func drawnSilhouette(doc: EditorDocument, width w: Int, height h: Int, scale: CGFloat) -> CGImage? {
        let dest = CGRect(
            x: doc.padding.left * scale,
            y: doc.padding.top * scale,
            width: doc.baseSelection.width * scale,
            height: doc.baseSelection.height * scale
        )
        let selectionPx = doc.baseSelection.integral.intersection(doc.imageBounds)
        guard !selectionPx.isNull, !selectionPx.isEmpty,
              let cropped = doc.screenshot.cropping(to: selectionPx) else { return nil }

        guard let rgba = CGContext(
            data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue
        ) else { return nil }
        rgba.interpolationQuality = .high
        let radii = doc.selectionCornerRadii.clamped(to: dest.size)
        if !radii.isZero {
            rgba.addPath(radii.path(in: dest))
            rgba.clip()
        }
        rgba.draw(cropped, in: dest)
        guard let rgbaImage = rgba.makeImage() else { return nil }

        // Move the alpha channel into luminance (opaque gray) so morphology
        // dilates the silhouette shape rather than the screenshot's colors.
        let gray = CIImage(cgImage: rgbaImage).applyingFilter("CIColorMatrix", parameters: [
            "inputRVector": CIVector(x: 0, y: 0, z: 0, w: 1),
            "inputGVector": CIVector(x: 0, y: 0, z: 0, w: 1),
            "inputBVector": CIVector(x: 0, y: 0, z: 0, w: 1),
            "inputAVector": CIVector(x: 0, y: 0, z: 0, w: 0),
            "inputBiasVector": CIVector(x: 0, y: 0, z: 0, w: 1)
        ])
        return ciContext.createCGImage(gray, from: CGRect(x: 0, y: 0, width: w, height: h))
    }

    /// Turn the gray luminance mask into a premultiplied white image whose alpha
    /// is the coverage, suitable as a CALayer mask's contents.
    private static func alphaImage(from grayMask: CGImage, width w: Int, height h: Int) -> CGImage? {
        guard let ctx = CGContext(
            data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue
        ) else { return nil }
        let rect = CGRect(x: 0, y: 0, width: w, height: h)
        ctx.clip(to: rect, mask: grayMask)
        ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        ctx.fill(rect)
        return ctx.makeImage()
    }

    private static let ciContext = CIContext(options: [.useSoftwareRenderer: false])
}

private final class Cache: @unchecked Sendable {
    static let shared = Cache()
    private let lock = NSLock()
    private var key: String?
    private var value: ConcentricCardMask.Coverage?

    func coverage(for doc: EditorDocument) -> ConcentricCardMask.Coverage? {
        let k = Self.key(for: doc)
        lock.lock()
        if k == key, let value { lock.unlock(); return value }
        lock.unlock()
        let built = ConcentricCardMask.build(for: doc)
        lock.lock(); key = k; value = built; lock.unlock()
        return built
    }

    private static func key(for doc: EditorDocument) -> String {
        let p = doc.padding
        return "\(ObjectIdentifier(doc.screenshot))|\(doc.baseSelection)|\(doc.selectionCornerRadii)|\(doc.contentCornerRadii)|\(p.top),\(p.right),\(p.bottom),\(p.left)"
    }
}
