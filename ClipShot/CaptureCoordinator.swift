import AppKit
import ImageIO
import UniformTypeIdentifiers

@MainActor
final class CaptureCoordinator: @unchecked Sendable {
    private let appState: AppState
    private let sessionStore = CaptureSessionStore()
    let recentsStore = RecentsStore()
    private var editorWindowController: EditorWindowController?

    init(appState: AppState) {
        self.appState = appState
    }

    /// Brings the editor window forward; with no session it shows the home page.
    /// A closed window reopens to the home page rather than a stale session.
    func showHome() {
        recentsStore.loadIfNeeded()
        let controller = ensureWindowController()
        if !controller.isWindowVisible {
            sessionStore.session = nil
        }
        controller.show()
    }

    /// Imports an image file as a new session; returns false if it can't be read.
    /// File IO and decoding happen off the main actor.
    @discardableResult
    func importImage(at url: URL) async -> Bool {
        let request = await Task.detached(priority: .userInitiated) {
            guard let data = try? Data(contentsOf: url) else { return CaptureSessionRequest?.none }
            return Self.makeImportRequest(imageData: data,
                                          sourceTitle: url.deletingPathExtension().lastPathComponent)
        }.value
        guard let request else { return importFailed() }
        return openSession(request: request)
    }

    /// Imports raw image data (e.g. dragged from a browser) as a new session.
    @discardableResult
    func importImage(data: Data, sourceTitle: String) async -> Bool {
        let request = await Task.detached(priority: .userInitiated) {
            Self.makeImportRequest(imageData: data, sourceTitle: sourceTitle)
        }.value
        guard let request else { return importFailed() }
        return openSession(request: request)
    }

    func openSession(request: CaptureSessionRequest) -> Bool {
        guard let session = presentSession(request: request) else { return false }
        recordRecent(session: session, request: request)
        return true
    }

    func reopenRecent(_ entry: RecentEntry) {
        // Ordered read: lands after any in-flight write for this entry, so nil means truly missing.
        recentsStore.imageData(for: entry) { [weak self] imageData in
            guard let self else { return }
            guard let imageData else {
                self.appState.setCaptureStatus("Recent capture is missing")
                NSSound.beep()
                self.recentsStore.remove(entry.id)
                return
            }

            let request = Self.makeReopenRequest(entry: entry, imageData: imageData)
            guard self.presentSession(request: request) != nil else { return }
            self.recentsStore.touch(entry.id)
        }
    }

    func openNativeScreenshot(image: CGImage,
                              pixelScale: CGFloat,
                              sourceAppName: String,
                              cornerRadii: CaptureCornerRadii? = nil) -> Bool {
        guard let pngData = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]) else {
            appState.setCaptureStatus("Could not encode screenshot")
            NSSound.beep()
            return false
        }

        let safeScale = max(1, pixelScale)
        let pixelWidth = Double(image.width)
        let pixelHeight = Double(image.height)
        let pointWidth = pixelWidth / Double(safeScale)
        let pointHeight = pixelHeight / Double(safeScale)
        let request = CaptureSessionRequest(
            screenshotBase64: pngData.base64EncodedString(),
            selectedRect: CaptureRect(left: 0, top: 0, width: pointWidth, height: pointHeight),
            viewport: CaptureViewport(
                width: pointWidth,
                height: pointHeight,
                devicePixelRatio: Double(safeScale),
                scrollX: 0,
                scrollY: 0
            ),
            candidates: [],
            selectedIndex: -1,
            sourceTitle: sourceAppName,
            sourceURL: "",
            imageWidth: pixelWidth,
            imageHeight: pixelHeight,
            selectedBorderRadii: nil,
            premaskedCornerRadii: cornerRadii
        )
        return openSession(request: request)
    }

    /// Builds a request equivalent to the entry's original capture; pure so it's unit-testable.
    static func makeReopenRequest(entry: RecentEntry, imageData: Data) -> CaptureSessionRequest {
        let scale = Double(max(1, entry.pixelScale))
        let pointWidth = Double(entry.pixelWidth) / scale
        let pointHeight = Double(entry.pixelHeight) / scale
        let selectedRect = entry.selectionRect.map {
            CaptureRect(left: $0.origin.x, top: $0.origin.y, width: $0.width, height: $0.height)
        } ?? CaptureRect(left: 0, top: 0, width: pointWidth, height: pointHeight)

        return CaptureSessionRequest(
            screenshotBase64: imageData.base64EncodedString(),
            selectedRect: selectedRect,
            viewport: CaptureViewport(
                width: pointWidth,
                height: pointHeight,
                devicePixelRatio: scale,
                scrollX: 0,
                scrollY: 0
            ),
            candidates: [],
            selectedIndex: -1,
            sourceTitle: entry.sourceTitle,
            sourceURL: "",
            imageWidth: Double(entry.pixelWidth),
            imageHeight: Double(entry.pixelHeight),
            selectedBorderRadii: nil,
            premaskedCornerRadii: entry.cornerRadii
        )
    }

    /// Builds a session request from arbitrary image-file data; pure so it's unit-testable.
    /// Selection covers the full frame; pixel scale comes from DPI metadata when present.
    nonisolated static func makeImportRequest(imageData: Data, sourceTitle: String) -> CaptureSessionRequest? {
        guard let source = CGImageSourceCreateWithData(imageData as CFData, nil) else { return nil }

        let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        let orientation = (properties?[kCGImagePropertyOrientation] as? NSNumber)?.uint32Value ?? 1
        let isPNG = (CGImageSourceGetType(source) as String?) == UTType.png.identifier
        let metaWidth = (properties?[kCGImagePropertyPixelWidth] as? NSNumber)?.doubleValue
        let metaHeight = (properties?[kCGImagePropertyPixelHeight] as? NSNumber)?.doubleValue

        let pngData: Data
        let pixelWidth: Double
        let pixelHeight: Double
        if isPNG, orientation == 1, let metaWidth, let metaHeight {
            // Already an upright PNG: keep the original bytes.
            pngData = imageData
            pixelWidth = metaWidth
            pixelHeight = metaHeight
        } else {
            // Full-size decode with EXIF orientation applied (same pattern as recents thumbnails).
            var options: [CFString: Any] = [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true
            ]
            if let metaWidth, let metaHeight {
                options[kCGImageSourceThumbnailMaxPixelSize] = max(metaWidth, metaHeight)
            }
            guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary),
                  let encoded = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])
            else { return nil }
            pngData = encoded
            pixelWidth = Double(image.width)
            pixelHeight = Double(image.height)
        }

        let dpi = (properties?[kCGImagePropertyDPIWidth] as? NSNumber)?.doubleValue ?? 0
        // Retina screenshots are typically saved at 144 DPI; map DPI to a 1–4x scale.
        let scale = dpi > 0 ? min(max((dpi / 72).rounded(), 1), 4) : 1
        let pointWidth = pixelWidth / scale
        let pointHeight = pixelHeight / scale

        return CaptureSessionRequest(
            screenshotBase64: pngData.base64EncodedString(),
            selectedRect: CaptureRect(left: 0, top: 0, width: pointWidth, height: pointHeight),
            viewport: CaptureViewport(
                width: pointWidth,
                height: pointHeight,
                devicePixelRatio: scale,
                scrollX: 0,
                scrollY: 0
            ),
            candidates: [],
            selectedIndex: -1,
            sourceTitle: sourceTitle,
            sourceURL: "",
            imageWidth: pixelWidth,
            imageHeight: pixelHeight,
            selectedBorderRadii: nil,
            premaskedCornerRadii: nil
        )
    }

    // MARK: - Private

    private func ensureWindowController() -> EditorWindowController {
        let controller = editorWindowController ?? EditorWindowController(
            store: sessionStore,
            recentsStore: recentsStore,
            onReopenRecent: { [weak self] entry in self?.reopenRecent(entry) },
            onImportFile: { [weak self] url in await self?.importImage(at: url) ?? false },
            onImportData: { [weak self] data, title in
                await self?.importImage(data: data, sourceTitle: title) ?? false
            }
        )
        editorWindowController = controller
        return controller
    }

    private func importFailed() -> Bool {
        appState.setCaptureStatus("Couldn't read that image")
        NSSound.beep()
        return false
    }

    private func presentSession(request: CaptureSessionRequest) -> CaptureSession? {
        do {
            let session = try CaptureSession(request: request)
            sessionStore.session = session
            recentsStore.loadIfNeeded()
            ensureWindowController().show()

            appState.setCaptureStatus("Editor session ready")
            return session
        } catch {
            appState.setCaptureStatus("Could not open editor session")
            NSSound.beep()
            return nil
        }
    }

    private func recordRecent(session: CaptureSession, request: CaptureSessionRequest) {
        let entry = RecentEntry(
            id: UUID(),
            capturedAt: session.capturedAt,
            sourceTitle: request.sourceTitle,
            pixelScale: CGFloat(request.viewport.devicePixelRatio),
            selectionRect: CGRect(
                x: request.selectedRect.left,
                y: request.selectedRect.top,
                width: request.selectedRect.width,
                height: request.selectedRect.height
            ),
            cornerRadii: request.premaskedCornerRadii,
            pixelWidth: Int(session.imagePixelSize.width),
            pixelHeight: Int(session.imagePixelSize.height)
        )
        recentsStore.record(imageData: session.screenshotData, entry: entry)
    }
}
