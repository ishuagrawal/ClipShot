import Foundation
import UniformTypeIdentifiers

/// A selectable wallpaper, either bundled with the app or user-imported.
struct Wallpaper: Identifiable, Equatable {
    let ref: WallpaperRef
    let category: String
    let subject: String?
    let tone: String?

    var id: String { ref.key }

    var displayName: String {
        if let subject, !subject.isEmpty { return subject.capitalized }
        return category.capitalized
    }
}

/// Reads the bundled `Wallpapers/` folder (+ its `ATTRIBUTION.json`) and manages
/// user uploads copied into Application Support.
enum WallpaperCatalog {
    static let categoryOrder = ["gradient", "aerial", "watercolor", "nature"]

    private struct Entry: Decodable {
        let file: String
        let category: String
        let subject: String?
        let tone: String?
    }

    private static let bundledCache: [Wallpaper] = loadBundled()

    static func bundledGroups() -> [(category: String, items: [Wallpaper])] {
        categoryOrder.compactMap { cat in
            let items = bundledCache.filter { $0.category == cat }
            return items.isEmpty ? nil : (cat, items)
        }
    }

    static func userUploads() -> [Wallpaper] {
        guard let dir = try? uploadsDirectory(create: false),
              let urls = try? FileManager.default.contentsOfDirectory(
                  at: dir, includingPropertiesForKeys: nil) else { return [] }
        return urls
            .filter { isImage($0) }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
            .map { Wallpaper(ref: .user($0), category: "upload", subject: nil, tone: nil) }
    }

    /// Copies the picked image into Application Support and returns its ref.
    static func importUpload(from source: URL) throws -> WallpaperRef {
        guard isImage(source) else { throw CatalogError.notAnImage }
        let dir = try uploadsDirectory(create: true)
        let ext = source.pathExtension.isEmpty ? "png" : source.pathExtension
        let dest = dir.appendingPathComponent("\(UUID().uuidString).\(ext)")
        try FileManager.default.copyItem(at: source, to: dest)
        return .user(dest)
    }

    /// Category of a bundled wallpaper ("gradient"/"abstract"/"nature"), or "upload" for user images.
    static func category(of ref: WallpaperRef) -> String? {
        switch ref {
        case .user: return "upload"
        case .bundled(let name): return bundledCache.first { $0.ref == .bundled(name) }?.category
        }
    }

    static func resolveURL(_ ref: WallpaperRef) -> URL? {
        switch ref {
        case .bundled(let name):
            return bundledFolder()?.appendingPathComponent(name)
        case .user(let url):
            return url
        }
    }

    // MARK: - Internals

    private static func bundledFolder() -> URL? {
        Bundle.main.url(forResource: "Wallpapers", withExtension: nil)
    }

    private static func loadBundled() -> [Wallpaper] {
        guard let folder = bundledFolder(),
              let data = try? Data(contentsOf: folder.appendingPathComponent("ATTRIBUTION.json")),
              let entries = try? JSONDecoder().decode([Entry].self, from: data) else { return [] }
        return entries.map {
            Wallpaper(ref: .bundled($0.file), category: $0.category,
                      subject: $0.subject, tone: $0.tone)
        }
    }

    static func uploadsDirectory(create: Bool) throws -> URL {
        let base = try FileManager.default.url(
            for: .applicationSupportDirectory, in: .userDomainMask,
            appropriateFor: nil, create: create)
        let dir = base.appendingPathComponent("ClipShot/Wallpapers", isDirectory: true)
        if create {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir
    }

    private static func isImage(_ url: URL) -> Bool {
        guard let type = UTType(filenameExtension: url.pathExtension) else { return false }
        return type.conforms(to: .image)
    }

    enum CatalogError: Error { case notAnImage }
}
