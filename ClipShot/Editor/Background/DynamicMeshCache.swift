import Foundation
import CoreGraphics

/// Caches the rendered dynamic-mesh background image, keyed by screenshot
/// identity, the sampled selection rect, and the output size. Mirrors the
/// shape of the former BlurExtendCache.
final class DynamicMeshCache: @unchecked Sendable {
    static let shared = DynamicMeshCache()

    /// The mesh is a low-frequency gradient, so rendering it above this size buys
    /// no visible detail — consumers upscale it (CALayer `.resize` in preview,
    /// `ctx.draw` stretch in export). Capping keeps padding-slider drags on large
    /// Retina captures off the main-thread per-pixel render hotpath.
    private static let maxRenderDimension = 512

    private let lock = NSLock()
    private var cachedImage: CGImage?
    private var cachedSource: CGImage?
    private var cachedSelection: CGRect = .null
    private var cachedSize: CGSize = .zero

    func meshImage(for screenshot: CGImage, selection: CGRect, size: CGSize) -> CGImage? {
        let w = max(1, Int(size.width.rounded()))
        let h = max(1, Int(size.height.rounded()))
        let key = CGSize(width: w, height: h)

        lock.lock()
        if let cachedImage, let cachedSource, cachedSource === screenshot,
           cachedSelection == selection, cachedSize == key {
            lock.unlock()
            return cachedImage
        }
        lock.unlock()

        let spec = MeshGradientGenerator.generate(screenshot: screenshot, selection: selection)
        guard let image = spec.render(size: Self.cappedSize(width: w, height: h)) else { return nil }

        lock.lock()
        cachedImage = image
        cachedSource = screenshot
        cachedSelection = selection
        cachedSize = key
        lock.unlock()
        return image
    }

    /// Aspect-preserving cap so the long side never exceeds `maxRenderDimension`.
    private static func cappedSize(width w: Int, height h: Int) -> CGSize {
        let longSide = max(w, h)
        guard longSide > maxRenderDimension else { return CGSize(width: w, height: h) }
        let scale = Double(maxRenderDimension) / Double(longSide)
        return CGSize(
            width: max(1, Int((Double(w) * scale).rounded())),
            height: max(1, Int((Double(h) * scale).rounded()))
        )
    }
}
