import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var captureCoordinator: CaptureCoordinator?
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
    }

    func applicationWillTerminate(_ notification: Notification) {
        nativeCaptureShortcut?.unregister()
    }
}
