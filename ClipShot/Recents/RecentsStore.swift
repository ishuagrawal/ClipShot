import CoreGraphics
import Foundation

struct RecentEntry: Identifiable, Codable, Sendable {
    let id: UUID
    let capturedAt: Date
    let sourceTitle: String?
    let pixelScale: CGFloat
    let selectionRect: CGRect?
    let cornerRadii: CaptureCornerRadii?
    let pixelWidth: Int
    let pixelHeight: Int
}

@MainActor
final class RecentsStore: ObservableObject {
    static let maxEntries = 20

    @Published private(set) var entries: [RecentEntry] = []

    private let rootURL: URL
    private let queue = DispatchQueue(label: "com.clipshot.recents-store", qos: .utility)
    private var didLoad = false

    init(rootURL: URL = RecentsStore.defaultRootURL()) {
        self.rootURL = rootURL
    }

    nonisolated static func defaultRootURL() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support", isDirectory: true)
        return base.appendingPathComponent("ClipShot/Recents", isDirectory: true)
    }

    nonisolated func imageURL(for entry: RecentEntry) -> URL {
        directoryURL(for: entry.id).appendingPathComponent("image.png")
    }

    nonisolated func imageData(for entry: RecentEntry) -> Data? {
        try? Data(contentsOf: imageURL(for: entry))
    }

    func record(imageData: Data, entry: RecentEntry) {
        // Insert synchronously so the UI updates immediately and remove() can't race the write.
        insert(entry)
        guard entries.contains(where: { $0.id == entry.id }) else { return } // pruned at insert
        let directory = directoryURL(for: entry.id)
        queue.async { [weak self] in
            guard !Self.write(imageData: imageData, entry: entry, to: directory) else { return }
            Task { @MainActor in
                NSLog("RecentsStore: dropping entry \(entry.id) after failed write")
                self?.entries.removeAll { $0.id == entry.id }
            }
        }
    }

    func loadIfNeeded() {
        guard !didLoad else { return }
        didLoad = true

        let root = rootURL
        queue.async { [weak self] in
            let loaded = Self.loadEntries(from: root)
            Task { @MainActor in
                guard let self else { return }
                let recorded = self.entries
                self.entries = (recorded + loaded.filter { entry in
                    !recorded.contains { $0.id == entry.id }
                }).sorted { $0.capturedAt > $1.capturedAt }
                self.pruneOverCap()
            }
        }
    }

    func remove(_ id: UUID) {
        entries.removeAll { $0.id == id }
        deleteDirectory(for: id)
    }

    // MARK: - Private

    private nonisolated func directoryURL(for id: UUID) -> URL {
        rootURL.appendingPathComponent(id.uuidString, isDirectory: true)
    }

    private func deleteDirectory(for id: UUID) {
        let url = directoryURL(for: id)
        queue.async {
            do {
                try FileManager.default.removeItem(at: url)
            } catch let error as NSError where error.domain == NSCocoaErrorDomain && error.code == NSFileNoSuchFileError {
                // Already gone (e.g. load-side cleanup); benign.
            } catch {
                NSLog("RecentsStore: failed to delete \(url.lastPathComponent): \(error)")
            }
        }
    }

    private func insert(_ entry: RecentEntry) {
        entries.removeAll { $0.id == entry.id }
        let index = entries.firstIndex { $0.capturedAt < entry.capturedAt } ?? entries.endIndex
        entries.insert(entry, at: index)
        pruneOverCap()
    }

    private func pruneOverCap() {
        guard entries.count > Self.maxEntries else { return }
        let pruned = Array(entries.suffix(from: Self.maxEntries))
        entries.removeLast(pruned.count)
        for entry in pruned {
            deleteDirectory(for: entry.id)
        }
    }

    private nonisolated static func write(imageData: Data, entry: RecentEntry, to directory: URL) -> Bool {
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try imageData.write(to: directory.appendingPathComponent("image.png"), options: .atomic)
            let meta = try JSONEncoder().encode(entry)
            try meta.write(to: directory.appendingPathComponent("meta.json"), options: .atomic)
            return true
        } catch {
            NSLog("RecentsStore: failed to write entry \(entry.id): \(error)")
            return false
        }
    }

    private nonisolated static func loadEntries(from root: URL) -> [RecentEntry] {
        let fileManager = FileManager.default
        guard let contents = try? fileManager.contentsOfDirectory(at: root, includingPropertiesForKeys: nil) else {
            return []
        }

        var loaded: [RecentEntry] = []
        for directory in contents {
            guard (try? directory.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true else { continue }
            let metaURL = directory.appendingPathComponent("meta.json")
            let imageURL = directory.appendingPathComponent("image.png")
            if let data = try? Data(contentsOf: metaURL),
               let entry = try? JSONDecoder().decode(RecentEntry.self, from: data),
               fileManager.fileExists(atPath: imageURL.path) {
                loaded.append(entry)
            } else {
                NSLog("RecentsStore: pruning invalid entry at \(directory.lastPathComponent)")
                try? fileManager.removeItem(at: directory)
            }
        }
        return loaded.sorted { $0.capturedAt > $1.capturedAt }
    }
}
