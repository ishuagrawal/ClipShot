import SwiftUI

@MainActor
final class AppState: ObservableObject {
    static let shared = AppState()

    @Published private(set) var lastCaptureStatus: String?

    /// Set by AppDelegate once the capture launcher exists; invoked from the menu bar.
    var onBeginCapture: (() -> Void)?

    /// Set by AppDelegate; opens the editor window (home page when no session).
    var onOpenHome: (() -> Void)?

    /// Set by AppDelegate; opens the Settings window.
    var onOpenSettings: (() -> Void)?

    /// Set by AppDelegate; toggles the global capture shortcut during shortcut recording.
    var onCaptureShortcutEnabledChanged: ((Bool) -> Void)?

    private init() {}

    func setCaptureStatus(_ status: String?) {
        lastCaptureStatus = status
    }
}
