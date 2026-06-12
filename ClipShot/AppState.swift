import SwiftUI

@MainActor
final class AppState: ObservableObject {
    static let shared = AppState()

    @Published private(set) var lastCaptureStatus: String?

    /// Set by AppDelegate once the capture launcher exists; invoked from the menu bar.
    var onBeginCapture: (() -> Void)?

    private init() {}

    func setCaptureStatus(_ status: String?) {
        lastCaptureStatus = status
    }
}
