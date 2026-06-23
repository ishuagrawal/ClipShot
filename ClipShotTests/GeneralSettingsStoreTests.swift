import XCTest
@testable import ClipShot

@MainActor
final class GeneralSettingsStoreTests: XCTestCase {

    private func makeStore() -> GeneralSettingsStore {
        let suite = "GeneralSettingsTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return GeneralSettingsStore(defaults: defaults)
    }

    func testDefaultSaveDirectoryIsDesktop() {
        let store = makeStore()
        let desktop = FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask).first!
        XCTAssertEqual(store.saveDirectoryURL.standardizedFileURL, desktop.standardizedFileURL)
    }

    func testSetSaveDirectoryPersists() {
        let suite = "GeneralSettingsTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)

        let temp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try! FileManager.default.createDirectory(at: temp, withIntermediateDirectories: true)

        let store = GeneralSettingsStore(defaults: defaults)
        store.setSaveDirectory(temp)

        let reloaded = GeneralSettingsStore(defaults: defaults)
        XCTAssertEqual(reloaded.saveDirectoryURL.standardizedFileURL, temp.standardizedFileURL)
    }

    func testDisplayPathAbbreviatesHomeDirectory() {
        let store = makeStore()
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let path = store.displayPath
        XCTAssertTrue(path.hasPrefix("~"))
        XCTAssertEqual(path, "~" + store.saveDirectoryURL.path.dropFirst(home.count))
    }
}