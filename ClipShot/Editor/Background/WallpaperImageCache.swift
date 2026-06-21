import Foundation
import CoreGraphics
import ImageIO

/// Loads and caches wallpaper bitmaps (full + thumbnail), keyed by ref.
/// Mirrors `DynamicMeshCache` so the renderer and panel share one decode path.
final class WallpaperImageCache: @unchecked Sendable {
    static let shared = WallpaperImageCache()

    private let lock = NSLock()
    private var full: [String: CGImage] = [:]
    private var thumbs: [String: CGImage] = [:]

    func image(for ref: WallpaperRef) -> CGImage? {
        let key = ref.key
        lock.lock()
        if let cached = full[key] { lock.unlock(); return cached }
        lock.unlock()

        guard let url = WallpaperCatalog.resolveURL(ref),
              let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { return nil }
        lock.lock(); full[key] = image; lock.unlock()
        return image
    }

    func thumbnail(for ref: WallpaperRef, maxPixel: Int) -> CGImage? {
        let key = "\(ref.key)#\(maxPixel)"
        lock.lock()
        if let cached = thumbs[key] { lock.unlock(); return cached }
        lock.unlock()

        guard let url = WallpaperCatalog.resolveURL(ref),
              let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixel
        ]
        guard let thumb = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
        else { return nil }
        lock.lock(); thumbs[key] = thumb; lock.unlock()
        return thumb
    }
}
