import AppKit

@MainActor
final class CaptureCoordinator: @unchecked Sendable {
    private let appState: AppState
    private let sessionStore = CaptureSessionStore()
    let recentsStore = RecentsStore()
    private var editorWindowController: EditorWindowController?

    init(appState: AppState) {
        self.appState = appState
    }

    func openSession(request: CaptureSessionRequest) -> Bool {
        guard let session = presentSession(request: request) else { return false }
        recordRecent(session: session, request: request)
        return true
    }

    func reopenRecent(_ entry: RecentEntry) {
        guard let imageData = recentsStore.imageData(for: entry) else {
            appState.setCaptureStatus("Recent capture is missing")
            NSSound.beep()
            recentsStore.remove(entry.id)
            return
        }

        let request = Self.makeReopenRequest(entry: entry, imageData: imageData)
        guard presentSession(request: request) != nil else { return }
        recentsStore.touch(entry.id)
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

    // MARK: - Private

    private func presentSession(request: CaptureSessionRequest) -> CaptureSession? {
        do {
            let session = try CaptureSession(request: request)
            sessionStore.session = session
            recentsStore.loadIfNeeded()

            let controller = editorWindowController ?? EditorWindowController(
                store: sessionStore,
                recentsStore: recentsStore,
                onReopenRecent: { [weak self] entry in self?.reopenRecent(entry) }
            )
            editorWindowController = controller
            controller.show()

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
