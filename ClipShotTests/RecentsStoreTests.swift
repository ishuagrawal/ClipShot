import XCTest
@testable import ClipShot

@MainActor
final class RecentsStoreTests: XCTestCase {

    private var rootURL: URL!

    override func setUpWithError() throws {
        rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("RecentsStoreTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: rootURL)
    }

    private func makeEntry(capturedAt: Date = Date(), title: String? = "Test") -> RecentEntry {
        RecentEntry(
            id: UUID(),
            capturedAt: capturedAt,
            sourceTitle: title,
            pixelScale: 2,
            selectionRect: CGRect(x: 10, y: 20, width: 300, height: 200),
            cornerRadii: nil,
            pixelWidth: 600,
            pixelHeight: 400
        )
    }

    // meta.json is written last, so its presence means the entry is fully on disk.
    private func waitForDisk(_ entry: RecentEntry) {
        let meta = rootURL.appendingPathComponent(entry.id.uuidString).appendingPathComponent("meta.json")
        wait { FileManager.default.fileExists(atPath: meta.path) }
    }

    private func wait(timeout: TimeInterval = 5, until condition: @escaping () -> Bool) {
        let deadline = Date(timeIntervalSinceNow: timeout)
        while !condition() && Date() < deadline {
            RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.02))
        }
        XCTAssertTrue(condition(), "Timed out waiting for condition")
    }

    func test_record_thenLoad_roundTripsEntryAndImage() {
        let store = RecentsStore(rootURL: rootURL)
        let entry = makeEntry()
        let imageData = Data([0x89, 0x50, 0x4E, 0x47, 0x01, 0x02, 0x03])

        store.record(imageData: imageData, entry: entry)
        XCTAssertEqual(store.entries.count, 1)
        waitForDisk(entry)

        let reloaded = RecentsStore(rootURL: rootURL)
        reloaded.loadIfNeeded()
        wait { reloaded.entries.count == 1 }

        let loaded = reloaded.entries[0]
        XCTAssertEqual(loaded.id, entry.id)
        XCTAssertEqual(loaded.sourceTitle, "Test")
        XCTAssertEqual(loaded.pixelScale, 2)
        XCTAssertEqual(loaded.selectionRect, entry.selectionRect)
        XCTAssertEqual(loaded.pixelWidth, 600)
        XCTAssertEqual(loaded.pixelHeight, 400)
        XCTAssertEqual(reloaded.imageData(for: loaded), imageData)
    }

    func test_entries_areNewestFirst() {
        let store = RecentsStore(rootURL: rootURL)
        let old = makeEntry(capturedAt: Date(timeIntervalSinceNow: -100), title: "old")
        let new = makeEntry(capturedAt: Date(), title: "new")

        store.record(imageData: Data([1]), entry: old)
        store.record(imageData: Data([2]), entry: new)
        waitForDisk(new)

        XCTAssertEqual(store.entries.map(\.sourceTitle), ["new", "old"])

        let reloaded = RecentsStore(rootURL: rootURL)
        reloaded.loadIfNeeded()
        wait { reloaded.entries.count == 2 }
        XCTAssertEqual(reloaded.entries.map(\.sourceTitle), ["new", "old"])
    }

    func test_record_prunesBeyondCap() {
        let store = RecentsStore(rootURL: rootURL)
        var oldest: RecentEntry?
        for i in 0..<25 {
            let entry = makeEntry(capturedAt: Date(timeIntervalSinceNow: TimeInterval(i)), title: "\(i)")
            if i == 0 { oldest = entry }
            store.record(imageData: Data([UInt8(i)]), entry: entry)
        }
        wait { store.entries.count == RecentsStore.maxEntries && store.entries.first?.sourceTitle == "24" }

        XCTAssertEqual(store.entries.count, RecentsStore.maxEntries)
        XCTAssertEqual(store.entries.last?.sourceTitle, "5")

        let oldestDir = rootURL.appendingPathComponent(oldest!.id.uuidString)
        wait { !FileManager.default.fileExists(atPath: oldestDir.path) }
    }

    func test_load_prunesCorruptMeta() throws {
        let store = RecentsStore(rootURL: rootURL)
        let good = makeEntry(title: "good")
        store.record(imageData: Data([1]), entry: good)
        waitForDisk(good)

        let corruptDir = rootURL.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: corruptDir, withIntermediateDirectories: true)
        try Data([1]).write(to: corruptDir.appendingPathComponent("image.png"))
        try Data("not json".utf8).write(to: corruptDir.appendingPathComponent("meta.json"))

        let reloaded = RecentsStore(rootURL: rootURL)
        reloaded.loadIfNeeded()
        wait { reloaded.entries.count == 1 }

        XCTAssertEqual(reloaded.entries[0].sourceTitle, "good")
        wait { !FileManager.default.fileExists(atPath: corruptDir.path) }
    }

    func test_load_prunesMissingImage() throws {
        let entry = makeEntry(title: "no-image")
        let dir = rootURL.appendingPathComponent(entry.id.uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try JSONEncoder().encode(entry).write(to: dir.appendingPathComponent("meta.json"))

        let store = RecentsStore(rootURL: rootURL)
        store.loadIfNeeded()
        wait { !FileManager.default.fileExists(atPath: dir.path) }
        XCTAssertTrue(store.entries.isEmpty)
    }

    func test_remove_deletesEntryAndDirectory() {
        let store = RecentsStore(rootURL: rootURL)
        let entry = makeEntry()
        store.record(imageData: Data([1]), entry: entry)
        wait { store.entries.count == 1 }

        store.remove(entry.id)
        XCTAssertTrue(store.entries.isEmpty)

        let dir = rootURL.appendingPathComponent(entry.id.uuidString)
        wait { !FileManager.default.fileExists(atPath: dir.path) }
    }

    func test_record_thenImmediateRemove_leavesNoEntryOrDirectory() {
        let store = RecentsStore(rootURL: rootURL)
        let entry = makeEntry()
        store.record(imageData: Data([1]), entry: entry)
        store.remove(entry.id)
        XCTAssertTrue(store.entries.isEmpty)

        // Sentinel write is queued after the entry's write + delete on the serial
        // queue, so once it lands all earlier async work has settled.
        let sentinel = makeEntry(title: "sentinel")
        store.record(imageData: Data([2]), entry: sentinel)
        waitForDisk(sentinel)

        let dir = rootURL.appendingPathComponent(entry.id.uuidString)
        XCTAssertFalse(FileManager.default.fileExists(atPath: dir.path))
        XCTAssertEqual(store.entries.map(\.id), [sentinel.id])
    }

    func test_loadIfNeeded_isIdempotent() {
        let writer = RecentsStore(rootURL: rootURL)
        let entry = makeEntry()
        writer.record(imageData: Data([1]), entry: entry)
        waitForDisk(entry)

        let store = RecentsStore(rootURL: rootURL)
        store.loadIfNeeded()
        wait { store.entries.count == 1 }
        store.loadIfNeeded()
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.1))
        XCTAssertEqual(store.entries.count, 1)
    }

    func test_touch_bumpsEntryToTopWithFreshDate() {
        let store = RecentsStore(rootURL: rootURL)
        let old = makeEntry(capturedAt: Date(timeIntervalSinceNow: -100), title: "old")
        let new = makeEntry(capturedAt: Date(timeIntervalSinceNow: -50), title: "new")
        store.record(imageData: Data([1]), entry: old)
        store.record(imageData: Data([2]), entry: new)
        XCTAssertEqual(store.entries.map(\.sourceTitle), ["new", "old"])

        store.touch(old.id)

        XCTAssertEqual(store.entries.map(\.sourceTitle), ["old", "new"])
        XCTAssertEqual(store.entries.count, 2)
        let bumped = store.entries[0]
        XCTAssertEqual(bumped.id, old.id)
        XCTAssertGreaterThan(bumped.capturedAt, old.capturedAt)
        XCTAssertEqual(bumped.selectionRect, old.selectionRect)
    }

    func test_touch_persistsAcrossReload() {
        let store = RecentsStore(rootURL: rootURL)
        let old = makeEntry(capturedAt: Date(timeIntervalSinceNow: -100), title: "old")
        let new = makeEntry(capturedAt: Date(timeIntervalSinceNow: -50), title: "new")
        store.record(imageData: Data([1]), entry: old)
        store.record(imageData: Data([2]), entry: new)
        waitForDisk(new)

        store.touch(old.id)
        // Touch's meta rewrite is queued behind the record writes; settle via sentinel meta read.
        let metaURL = rootURL.appendingPathComponent(old.id.uuidString).appendingPathComponent("meta.json")
        wait {
            guard let data = try? Data(contentsOf: metaURL),
                  let entry = try? JSONDecoder().decode(RecentEntry.self, from: data) else { return false }
            return entry.capturedAt > old.capturedAt
        }

        let reloaded = RecentsStore(rootURL: rootURL)
        reloaded.loadIfNeeded()
        wait { reloaded.entries.count == 2 }
        XCTAssertEqual(reloaded.entries.map(\.sourceTitle), ["old", "new"])
    }

    func test_touch_unknownID_isNoOp() {
        let store = RecentsStore(rootURL: rootURL)
        let entry = makeEntry()
        store.record(imageData: Data([1]), entry: entry)

        store.touch(UUID())
        XCTAssertEqual(store.entries.map(\.id), [entry.id])
    }

    func test_makeReopenRequest_mirrorsEntryMetadata() throws {
        let entry = makeEntry()
        let imageData = Data([0x01, 0x02])
        let request = CaptureCoordinator.makeReopenRequest(entry: entry, imageData: imageData)

        XCTAssertEqual(request.screenshotBase64, imageData.base64EncodedString())
        XCTAssertEqual(request.sourceTitle, entry.sourceTitle)
        XCTAssertEqual(request.viewport.devicePixelRatio, 2)
        XCTAssertEqual(request.viewport.width, 300) // 600px / 2x
        XCTAssertEqual(request.viewport.height, 200)
        XCTAssertEqual(request.imageWidth, 600)
        XCTAssertEqual(request.imageHeight, 400)
        XCTAssertEqual(request.selectedRect, CaptureRect(left: 10, top: 20, width: 300, height: 200))
        XCTAssertNil(request.premaskedCornerRadii)
    }

    func test_makeReopenRequest_withoutSelection_usesFullFrame() {
        var entry = makeEntry()
        entry = RecentEntry(
            id: entry.id,
            capturedAt: entry.capturedAt,
            sourceTitle: entry.sourceTitle,
            pixelScale: entry.pixelScale,
            selectionRect: nil,
            cornerRadii: entry.cornerRadii,
            pixelWidth: entry.pixelWidth,
            pixelHeight: entry.pixelHeight
        )
        let request = CaptureCoordinator.makeReopenRequest(entry: entry, imageData: Data([1]))
        XCTAssertEqual(request.selectedRect, CaptureRect(left: 0, top: 0, width: 300, height: 200))
    }

    func test_loadIfNeeded_afterRecord_doesNotDuplicateEntry() {
        let store = RecentsStore(rootURL: rootURL)
        let entry = makeEntry()
        store.record(imageData: Data([1]), entry: entry)
        XCTAssertEqual(store.entries.count, 1)
        waitForDisk(entry)

        store.loadIfNeeded()
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.2))
        XCTAssertEqual(store.entries.count, 1)
        XCTAssertEqual(store.entries[0].id, entry.id)
    }
}
