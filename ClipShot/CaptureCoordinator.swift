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

    private func reportCopyResult(_ didCopy: Bool) {
        if !didCopy {
            appState.setCaptureStatus("Clipboard write failed")
            NSSound.beep()
        }
    }
}
