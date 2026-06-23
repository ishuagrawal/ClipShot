import AppKit
import Combine

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var captureCoordinator: CaptureCoordinator?
    private var nativeCaptureLauncher: NativeCaptureLauncher?
    private var nativeCaptureShortcut: NativeCaptureShortcut?
    private let settingsWindowController = SettingsWindowController()
    private var captureBinding: KeyBinding?
    private var captureShortcutEnabled = true
    private var cancellables: Set<AnyCancellable> = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        let coordinator = CaptureCoordinator(appState: AppState.shared)
        captureCoordinator = coordinator
        let launcher = NativeCaptureLauncher(coordinator: coordinator, appState: AppState.shared)
        nativeCaptureLauncher = launcher
        let beginCapture: () -> Void = { [weak launcher] in
            launcher?.beginCapture()
        }
        AppState.shared.onBeginCapture = beginCapture
        AppState.shared.onOpenHome = { [weak coordinator] in
            coordinator?.showHome()
        }
        AppState.shared.onOpenSettings = { [weak self] in
            self?.settingsWindowController.show()
        }
        AppState.shared.onCaptureShortcutEnabledChanged = { [weak self] enabled in
            self?.setCaptureShortcutEnabled(enabled)
        }

        let shortcut = NativeCaptureShortcut(handler: beginCapture)
        if !shortcut.register() {
            AppState.shared.setCaptureStatus("Capture shortcut unavailable")
        }
        nativeCaptureShortcut = shortcut
        captureBinding = ShortcutStore.shared.binding(for: .capture)

        // Re-register the global hotkey whenever the user rebinds capture.
        ShortcutStore.shared.$overrides
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.reloadCaptureShortcutIfNeeded() }
            .store(in: &cancellables)
    }

    private func reloadCaptureShortcutIfNeeded() {
        let current = ShortcutStore.shared.binding(for: .capture)
        guard current != captureBinding else { return }
        captureBinding = current
        guard captureShortcutEnabled else { return }
        if nativeCaptureShortcut?.reload() == false {
            AppState.shared.setCaptureStatus("Capture shortcut unavailable")
        }
    }

    private func setCaptureShortcutEnabled(_ enabled: Bool) {
        guard enabled != captureShortcutEnabled else { return }
        captureShortcutEnabled = enabled
        if enabled {
            if nativeCaptureShortcut?.register() == false {
                AppState.shared.setCaptureStatus("Capture shortcut unavailable")
            }
        } else {
            nativeCaptureShortcut?.unregister()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        nativeCaptureShortcut?.unregister()
    }
}
