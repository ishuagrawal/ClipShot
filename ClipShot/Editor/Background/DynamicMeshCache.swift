import Foundation
import CoreGraphics

/// Caches the rendered dynamic-mesh background image, keyed by screenshot
/// identity, the sampled selection rect, and the output size. Mirrors the
/// shape of the former BlurExtendCache.
final class DynamicMeshCache: @unchecked Sendable {
    static let shared = DynamicMeshCache()

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
        guard let image = spec.render(size: key) else { return nil }

        lock.lock()
        cachedImage = image
        cachedSource = screenshot
        cachedSelection = selection
        cachedSize = key
        lock.unlock()
        return image
    }
}
