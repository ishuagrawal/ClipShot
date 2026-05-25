import SwiftUI

@MainActor
final class AppState: ObservableObject {
    static let shared = AppState()

    @Published private(set) var hasScreenRecordingPermission = false
    @Published private(set) var hasAccessibilityPermission = false
    @Published private(set) var lastCaptureStatus: String?

    weak var captureCoordinator: CaptureCoordinator?
    private var permissionTimer: Timer?

    private init() {}

    var isReadyForCapture: Bool {
        hasScreenRecordingPermission && hasAccessibilityPermission
    }

    func refreshPermissions() {
        hasScreenRecordingPermission = PermissionManager.hasScreenRecordingPermission
        hasAccessibilityPermission = PermissionManager.hasAccessibilityPermission
    }

    func startPermissionPolling() {
        refreshPermissions()
        permissionTimer?.invalidate()
        permissionTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.refreshPermissions()
            }
        }
    }

    func stopPermissionPolling() {
        permissionTimer?.invalidate()
        permissionTimer = nil
    }

    func requestScreenRecordingPermission() {
        PermissionManager.requestScreenRecordingPermission()
        refreshPermissions()
    }

    func requestAccessibilityPermission() {
        PermissionManager.requestAccessibilityPermission()
        refreshPermissions()
        if !hasAccessibilityPermission {
            lastCaptureStatus = "After enabling Accessibility, relaunch ClipShot if this still says Required."
        }
    }

    func openScreenRecordingSettings() {
        PermissionManager.openScreenRecordingSettings()
    }

    func openAccessibilitySettings() {
        PermissionManager.openAccessibilitySettings()
    }

    func startCapture() {
        refreshPermissions()
        captureCoordinator?.startCapture()
    }

    func setCaptureStatus(_ status: String?) {
        lastCaptureStatus = status
    }
}
