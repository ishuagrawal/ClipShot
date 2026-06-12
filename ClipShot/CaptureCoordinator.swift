import AppKit

@MainActor
final class CaptureCoordinator: @unchecked Sendable {
    private let appState: AppState
    private let sessionStore = CaptureSessionStore()
    private var editorWindowController: EditorWindowController?

    init(appState: AppState) {
        self.appState = appState
    }

    func openSession(request: CaptureSessionRequest) -> Bool {
        do {
            let session = try CaptureSession(request: request)
            sessionStore.session = session

            let controller = editorWindowController ?? EditorWindowController(store: sessionStore)
            editorWindowController = controller
            controller.show()

            appState.setCaptureStatus("Editor session ready")
            return true
        } catch {
            appState.setCaptureStatus("Could not open editor session")
            NSSound.beep()
            return false
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
}
