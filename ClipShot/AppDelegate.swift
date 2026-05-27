import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var captureCoordinator: CaptureCoordinator?
    private var domBridgeServer: DOMCaptureBridgeServer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let coordinator = CaptureCoordinator(appState: AppState.shared)
        captureCoordinator = coordinator
        startDOMBridgeServer(coordinator: coordinator)
    }

    func applicationWillTerminate(_ notification: Notification) {
        domBridgeServer?.stop()
    }

    private func startDOMBridgeServer(coordinator: CaptureCoordinator) {
        let server = DOMCaptureBridgeServer(
            clipboardHandler: { [coordinator] pngData in
                await MainActor.run {
                    coordinator.copyDOMPNGToClipboard(pngData: pngData)
                }
            },
            statusHandler: { status in
                await MainActor.run {
                    AppState.shared.setCaptureStatus(status)
                }
            }
        )
        server.start()
        domBridgeServer = server
    }
}
