import AppKit

@MainActor
final class CaptureCoordinator: @unchecked Sendable {
    private let appState: AppState

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

    private func reportCopyResult(_ didCopy: Bool) {
        if !didCopy {
            appState.setCaptureStatus("Clipboard write failed")
            NSSound.beep()
        }
    }
}
