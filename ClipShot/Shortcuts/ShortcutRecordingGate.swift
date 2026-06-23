import Foundation

@MainActor
final class ShortcutRecordingGate {
    private var isRecording = false
    private let setCaptureShortcutEnabled: @MainActor (Bool) -> Void

    init(setCaptureShortcutEnabled: @escaping @MainActor (Bool) -> Void = {
        AppState.shared.onCaptureShortcutEnabledChanged?($0)
    }) {
        self.setCaptureShortcutEnabled = setCaptureShortcutEnabled
    }

    func beginRecording() {
        guard !isRecording else { return }
        isRecording = true
        setCaptureShortcutEnabled(false)
    }

    func endRecording() {
        guard isRecording else { return }
        isRecording = false
        setCaptureShortcutEnabled(true)
    }
}
