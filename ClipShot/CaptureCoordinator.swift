import AppKit

@MainActor
final class CaptureCoordinator: @unchecked Sendable {
    private let appState: AppState
    private let sessionStore = DOMCaptureSessionStore()
    private var editorWindowController: EditorWindowController?

    init(appState: AppState) {
        self.appState = appState
    }

    func copyDOMPNGToClipboard(pngData: Data) -> Bool {
        guard !pngData.isEmpty else {
            reportCopyResult(false)
            return false
        }

        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        let didCopy = pasteboard.setData(pngData, forType: .png)
        reportCopyResult(didCopy)
        return didCopy
    }

    func openDOMSession(request: DOMCaptureSessionRequest) -> Bool {
        do {
            let session = try DOMCaptureSession(request: request)
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
                              cornerRadii: DOMCornerRadii? = nil) -> Bool {
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
        let request = DOMCaptureSessionRequest(
            screenshotBase64: pngData.base64EncodedString(),
            selectedRect: DOMCaptureRect(left: 0, top: 0, width: pointWidth, height: pointHeight),
            viewport: DOMCaptureViewport(
                width: pointWidth,
                height: pointHeight,
                devicePixelRatio: Double(safeScale),
                scrollX: 0,
                scrollY: 0
            ),
            candidates: [],
            selectedIndex: -1,
            pageTitle: sourceAppName,
            pageURL: "",
            imageWidth: pixelWidth,
            imageHeight: pixelHeight,
            selectedBorderRadii: cornerRadii
        )
        return openDOMSession(request: request)
    }

    private func reportCopyResult(_ didCopy: Bool) {
        if !didCopy {
            appState.setCaptureStatus("Clipboard write failed")
            NSSound.beep()
        }
    }
}
