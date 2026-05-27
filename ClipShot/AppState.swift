import SwiftUI

@MainActor
final class AppState: ObservableObject {
    static let shared = AppState()

    @Published private(set) var lastCaptureStatus: String?

    private init() {}

    func setCaptureStatus(_ status: String?) {
        lastCaptureStatus = status
    }
}
