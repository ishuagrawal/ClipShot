import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var captureCoordinator: CaptureCoordinator?
    private var domBridgeServer: DOMCaptureBridgeServer?
    private var nativeCaptureLauncher: NativeCaptureLauncher?
    private var nativeCaptureShortcut: NativeCaptureShortcut?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let coordinator = CaptureCoordinator(appState: AppState.shared)
        captureCoordinator = coordinator
        let launcher = NativeCaptureLauncher(coordinator: coordinator, appState: AppState.shared)
        nativeCaptureLauncher = launcher
        let shortcut = NativeCaptureShortcut { [weak launcher] in
            launcher?.beginCapture()
        }
        if !shortcut.register() {
            AppState.shared.setCaptureStatus("Control Shift 5 unavailable")
        }
        nativeCaptureShortcut = shortcut
        startDOMBridgeServer(coordinator: coordinator)
    }

    func applicationWillTerminate(_ notification: Notification) {
        nativeCaptureShortcut?.unregister()
        domBridgeServer?.stop()
    }

    private func startDOMBridgeServer(coordinator: CaptureCoordinator) {
        let server = DOMCaptureBridgeServer(
            clipboardHandler: { [coordinator] pngData in
                await MainActor.run {
                    coordinator.copyDOMPNGToClipboard(pngData: pngData)
                }
            },
            sessionHandler: { [coordinator] request in
                await MainActor.run {
                    coordinator.openDOMSession(request: request)
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
