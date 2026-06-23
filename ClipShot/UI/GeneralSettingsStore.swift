import Combine
import Foundation

/// Persists the default folder used when saving exported images.
@MainActor
final class GeneralSettingsStore: ObservableObject {
    static let shared = GeneralSettingsStore()

    @Published private(set) var saveDirectoryURL: URL

    private let defaults: UserDefaults
    private let storageKey = "ClipShotDefaultSaveDirectory"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.saveDirectoryURL = Self.resolveStoredOrDefault(from: defaults, key: storageKey)
    }

    func setSaveDirectory(_ url: URL) {
        let standardized = url.standardizedFileURL
        guard Self.isUsableDirectory(standardized) else { return }
        saveDirectoryURL = standardized
        persist()
    }

    /// Home-relative path for display (e.g. `~/Desktop`).
    var displayPath: String {
        let path = saveDirectoryURL.path
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        guard path.hasPrefix(home) else { return path }
        return "~" + path.dropFirst(home.count)
    }

    // MARK: - Persistence

    private func persist() {
        defaults.set(saveDirectoryURL.path, forKey: storageKey)
    }

    private static func resolveStoredOrDefault(from defaults: UserDefaults, key: String) -> URL {
        if let stored = defaults.string(forKey: key) {
            let url = URL(fileURLWithPath: stored, isDirectory: true).standardizedFileURL
            if isUsableDirectory(url) { return url }
        }
        return defaultSaveDirectory()
    }

    static func defaultSaveDirectory() -> URL {
        FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser
    }

    private static func isUsableDirectory(_ url: URL) -> Bool {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory),
              isDirectory.boolValue else {
            return false
        }
        return FileManager.default.isWritableFile(atPath: url.path)
    }
}