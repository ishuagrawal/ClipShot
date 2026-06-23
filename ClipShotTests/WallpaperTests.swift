import XCTest
import ImageIO
import UniformTypeIdentifiers
@testable import ClipShot

final class WallpaperTests: XCTestCase {

    // MARK: - Model

    func test_imageStyle_kindAndEquality() {
        let a = BackgroundStyle.image(.bundled("gradient-03.jpg"))
        XCTAssertEqual(a.kind, .wallpaper)
        XCTAssertEqual(a, .image(.bundled("gradient-03.jpg")))
        XCTAssertNotEqual(a, .image(.bundled("nature-01.jpg")))
    }

    func test_wallpaperRef_keyIsStable() {
        XCTAssertEqual(WallpaperRef.bundled("a.jpg").key, "bundled:a.jpg")
        let url = URL(fileURLWithPath: "/tmp/sub/photo.png")
        XCTAssertEqual(WallpaperRef.user(url).key, "user:photo.png")
    }

    func test_wallpaperImageCache_evictsOldFullImages() throws {
        let cache = WallpaperImageCache(fullLimit: 2, thumbnailLimit: 8)

        XCTAssertNotNil(cache.image(for: .bundled("gradient-01.jpg")))
        XCTAssertNotNil(cache.image(for: .bundled("gradient-02.jpg")))
        XCTAssertNotNil(cache.image(for: .bundled("gradient-03.jpg")))

        XCTAssertEqual(cache.cachedFullImageCount, 2)
        XCTAssertFalse(cache.isFullImageCached(for: .bundled("gradient-01.jpg")))
        XCTAssertTrue(cache.isFullImageCached(for: .bundled("gradient-02.jpg")))
        XCTAssertTrue(cache.isFullImageCached(for: .bundled("gradient-03.jpg")))
    }

    func test_wallpaperImageCache_retouchesFullImagesOnHit() throws {
        let cache = WallpaperImageCache(fullLimit: 2, thumbnailLimit: 8)

        XCTAssertNotNil(cache.image(for: .bundled("gradient-01.jpg")))
        XCTAssertNotNil(cache.image(for: .bundled("gradient-02.jpg")))
        XCTAssertNotNil(cache.image(for: .bundled("gradient-01.jpg")))
        XCTAssertNotNil(cache.image(for: .bundled("gradient-03.jpg")))

        XCTAssertEqual(cache.cachedFullImageCount, 2)
        XCTAssertTrue(cache.isFullImageCached(for: .bundled("gradient-01.jpg")))
        XCTAssertFalse(cache.isFullImageCached(for: .bundled("gradient-02.jpg")))
        XCTAssertTrue(cache.isFullImageCached(for: .bundled("gradient-03.jpg")))
    }

    func test_wallpaperImageCache_evictsOldThumbnails() throws {
        let cache = WallpaperImageCache(fullLimit: 2, thumbnailLimit: 2)

        XCTAssertNotNil(cache.thumbnail(for: .bundled("gradient-01.jpg"), maxPixel: 64))
        XCTAssertNotNil(cache.thumbnail(for: .bundled("gradient-02.jpg"), maxPixel: 64))
        XCTAssertNotNil(cache.thumbnail(for: .bundled("gradient-03.jpg"), maxPixel: 64))

        XCTAssertEqual(cache.cachedThumbnailCount, 2)
        XCTAssertFalse(cache.isThumbnailCached(for: .bundled("gradient-01.jpg"), maxPixel: 64))
        XCTAssertTrue(cache.isThumbnailCached(for: .bundled("gradient-02.jpg"), maxPixel: 64))
        XCTAssertTrue(cache.isThumbnailCached(for: .bundled("gradient-03.jpg"), maxPixel: 64))
    }

    func test_backgroundPaletteRequest_changesWhenCropAspectChanges() throws {
        let ref = WallpaperRef.bundled("a.jpg")
        let wide = try XCTUnwrap(BackgroundPaletteRequest(
            background: .image(ref),
            effectiveCrop: CGRect(x: 0, y: 0, width: 200, height: 100)
        ))
        let tall = try XCTUnwrap(BackgroundPaletteRequest(
            background: .image(ref),
            effectiveCrop: CGRect(x: 0, y: 0, width: 100, height: 200)
        ))

        XCTAssertNotEqual(wide.key, tall.key)
    }

    func test_backgroundPaletteRequest_rejectsStaleBackground() throws {
        let request = try XCTUnwrap(BackgroundPaletteRequest(
            background: .image(.bundled("a.jpg")),
            effectiveCrop: CGRect(x: 0, y: 0, width: 200, height: 100)
        ))

        XCTAssertFalse(request.matches(
            background: .image(.bundled("b.jpg")),
            effectiveCrop: CGRect(x: 0, y: 0, width: 200, height: 100),
            currentKey: request.key
        ))
        XCTAssertFalse(request.matches(
            background: .solidColor(CGColor(gray: 0, alpha: 1)),
            effectiveCrop: CGRect(x: 0, y: 0, width: 200, height: 100),
            currentKey: request.key
        ))
    }

    func test_backgroundLandingIdentity_changesWhenCropChanges() {
        let background = BackgroundStyle.image(.bundled("a.jpg"))
        let wide = CanvasBackgroundLanding(
            background: background,
            effectiveCrop: CGRect(x: 0, y: 0, width: 200, height: 100)
        )
        let tall = CanvasBackgroundLanding(
            background: background,
            effectiveCrop: CGRect(x: 0, y: 0, width: 100, height: 200)
        )

        XCTAssertNotEqual(wide, tall)
    }

    // MARK: - Aspect fill

    func test_aspectFill_coversAndCenters() {
        let rect = CGRect(x: 0, y: 0, width: 200, height: 200)
        let fill = DocumentRenderer.aspectFillRect(CGSize(width: 100, height: 50), in: rect)
        XCTAssertEqual(fill.width, 400, accuracy: 0.01)
        XCTAssertEqual(fill.height, 200, accuracy: 0.01)
        XCTAssertEqual(fill.midX, rect.midX, accuracy: 0.01)
        XCTAssertEqual(fill.midY, rect.midY, accuracy: 0.01)
        XCTAssertLessThanOrEqual(fill.minX, rect.minX)
        XCTAssertLessThanOrEqual(fill.minY, rect.minY)
    }

    // MARK: - Catalog uploads

    func test_importUpload_rejectsNonImage() throws {
        let txt = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(UUID().uuidString).txt")
        try "hi".write(to: txt, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: txt) }
        XCTAssertThrowsError(try WallpaperCatalog.importUpload(from: txt))
    }

    // MARK: - Rendering

    func test_render_imageBackground_fillsMarginOpaque() throws {
        let wallpaper = try writeTempPNG(
            color: CGColor(srgbRed: 0.9, green: 0.1, blue: 0.1, alpha: 1),
            size: CGSize(width: 40, height: 40))
        defer { try? FileManager.default.removeItem(at: wallpaper) }

        let screenshot = FixtureDocument.makeSolidImage(
            color: CGColor(srgbRed: 0.1, green: 0.2, blue: 0.9, alpha: 1),
            size: CGSize(width: 60, height: 60))
        let doc = EditorDocument(
            screenshot: screenshot,
            viewport: CGSize(width: 60, height: 60),
            sourceTitle: "t", sourceURL: "u",
            baseSelection: CGRect(x: 0, y: 0, width: 60, height: 60),
            padding: PaddingConfig(top: 24, right: 24, bottom: 24, left: 24),
            background: .image(.user(wallpaper)))

        let image = try XCTUnwrap(DocumentRenderer.render(doc))
        let buf = try XCTUnwrap(PixelBuffer.decode(image))
        let i = (6 * buf.bytesPerRow) + 6 * 4
        XCTAssertEqual(Int(buf.pixels[i + 3]), 255, "wallpaper margin must be opaque")
        XCTAssertGreaterThan(Int(buf.pixels[i + 0]), Int(buf.pixels[i + 2]) + 30,
                             "margin should show the red wallpaper, not the blue screenshot")
    }

    private func writeTempPNG(color: CGColor, size: CGSize) throws -> URL {
        let image = FixtureDocument.makeSolidImage(color: color, size: size)
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(UUID().uuidString).png")
        let dest = try XCTUnwrap(CGImageDestinationCreateWithURL(
            url as CFURL, UTType.png.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(dest, image, nil)
        XCTAssertTrue(CGImageDestinationFinalize(dest))
        return url
    }
}
