import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var hotKeyManager: HotKeyManager?
    private var captureCoordinator: CaptureCoordinator?
    private var domBridgeServer: DOMCaptureBridgeServer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let coordinator = CaptureCoordinator(appState: AppState.shared)
        captureCoordinator = coordinator
        AppState.shared.captureCoordinator = coordinator
        AppState.shared.startPermissionPolling()
        startDOMBridgeServer(coordinator: coordinator)

        let manager = HotKeyManager {
            Task { @MainActor in
                AppState.shared.startCapture()
            }
        }
        if !manager.register() {
            AppState.shared.setCaptureStatus("Hotkey registration failed. Use Capture Component from the menu.")
        }
        hotKeyManager = manager
    }

    func applicationWillTerminate(_ notification: Notification) {
        AppState.shared.stopPermissionPolling()
        domBridgeServer?.stop()
        hotKeyManager?.unregister()
    }

    private func startDOMBridgeServer(coordinator: CaptureCoordinator) {
        let server = DOMCaptureBridgeServer(
            clipboardHandler: { [weak coordinator] pngData in
                await MainActor.run {
                    coordinator?.copyDOMPNGToClipboard(pngData: pngData) ?? false
                }
            },
            screenCaptureHandler: { [weak coordinator] screenFrame in
                await MainActor.run {
                    coordinator?.copyDOMScreenFrameToClipboard(screenFrame: screenFrame) ?? false
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
