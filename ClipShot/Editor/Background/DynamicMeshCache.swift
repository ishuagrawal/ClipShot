import Foundation
import CoreGraphics

/// Caches a normalized dynamic-mesh background image, keyed by screenshot
/// identity and the sampled selection rect.
final class DynamicMeshCache: @unchecked Sendable {
    static let shared = DynamicMeshCache()

    /// The mesh is defined in normalized coordinates, so one square bitmap can
    /// be stretched to every card size without regenerating it during padding edits.
    private static let renderSize = CGSize(width: 512, height: 512)

    private let lock = NSLock()
    private var cachedImage: CGImage?
    private var cachedSource: CGImage?
    private var cachedSelection: CGRect = .null
    private var latestRequestSource: CGImage?
    private var latestRequestSelection: CGRect = .null

    func cachedMeshImage(for screenshot: CGImage, selection: CGRect) -> CGImage? {
        lock.lock()
        defer { lock.unlock() }
        if let cachedImage, let cachedSource, cachedSource === screenshot,
           cachedSelection == selection {
            return cachedImage
        }
        return nil
    }

    func meshImage(for screenshot: CGImage, selection: CGRect) -> CGImage? {
        lock.lock()
        if let cachedImage, let cachedSource, cachedSource === screenshot,
           cachedSelection == selection {
            lock.unlock()
            return cachedImage
        }
        latestRequestSource = screenshot
        latestRequestSelection = selection
        lock.unlock()

        let spec = MeshGradientGenerator.generate(screenshot: screenshot, selection: selection)
        guard let image = spec.render(size: Self.renderSize) else { return nil }

        lock.lock()
        if latestRequestSource === screenshot, latestRequestSelection == selection {
            cachedImage = image
            cachedSource = screenshot
            cachedSelection = selection
        }
        lock.unlock()
        return image
    }
}
