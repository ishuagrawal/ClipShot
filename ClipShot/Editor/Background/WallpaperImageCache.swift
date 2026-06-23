import Foundation
import CoreGraphics
import ImageIO

/// Loads and caches wallpaper bitmaps (full + thumbnail), keyed by ref.
/// Mirrors `DynamicMeshCache` so the renderer and panel share one decode path.
final class WallpaperImageCache: @unchecked Sendable {
    static let shared = WallpaperImageCache()

    private let fullLimit: Int
    private let thumbnailLimit: Int
    private let lock = NSLock()
    private var full: [String: CGImage] = [:]
    private var thumbs: [String: CGImage] = [:]
    private var fullOrder: [String] = []
    private var thumbnailOrder: [String] = []

    init(fullLimit: Int = 4, thumbnailLimit: Int = 32) {
        self.fullLimit = max(0, fullLimit)
        self.thumbnailLimit = max(0, thumbnailLimit)
    }

    func image(for ref: WallpaperRef) -> CGImage? {
        let key = ref.key
        lock.lock()
        if let cached = full[key] {
            touch(key, in: &fullOrder)
            lock.unlock()
            return cached
        }
        lock.unlock()

        guard let url = WallpaperCatalog.resolveURL(ref),
              let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { return nil }
        lock.lock()
        insert(image, for: key, into: &full, order: &fullOrder, limit: fullLimit)
        lock.unlock()
        return image
    }

    func thumbnail(for ref: WallpaperRef, maxPixel: Int) -> CGImage? {
        let key = "\(ref.key)#\(maxPixel)"
        lock.lock()
        if let cached = thumbs[key] {
            touch(key, in: &thumbnailOrder)
            lock.unlock()
            return cached
        }
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
        lock.lock()
        insert(thumb, for: key, into: &thumbs, order: &thumbnailOrder, limit: thumbnailLimit)
        lock.unlock()
        return thumb
    }

    var cachedFullImageCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return full.count
    }

    var cachedThumbnailCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return thumbs.count
    }

    func isFullImageCached(for ref: WallpaperRef) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return full[ref.key] != nil
    }

    func isThumbnailCached(for ref: WallpaperRef, maxPixel: Int) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return thumbs["\(ref.key)#\(maxPixel)"] != nil
    }

    private func insert(
        _ image: CGImage,
        for key: String,
        into cache: inout [String: CGImage],
        order: inout [String],
        limit: Int
    ) {
        guard limit > 0 else { return }
        cache[key] = image
        touch(key, in: &order)
        while order.count > limit, let evicted = order.first {
            order.removeFirst()
            cache[evicted] = nil
        }
    }

    private func touch(_ key: String, in order: inout [String]) {
        order.removeAll { $0 == key }
        order.append(key)
    }
}
