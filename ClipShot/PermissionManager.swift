import AppKit
import ApplicationServices
import CoreGraphics

enum PermissionManager {
    static var hasAccessibilityPermission: Bool {
        AXIsProcessTrusted()
    }

    static var hasScreenRecordingPermission: Bool {
        CGPreflightScreenCaptureAccess()
    }

    static func requestAccessibilityPermission() {
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }

    static func requestScreenRecordingPermission() {
        _ = CGRequestScreenCaptureAccess()
    }

    static func openAccessibilitySettings() {
        openPrivacySettings(anchor: "Privacy_Accessibility")
    }

    static func openScreenRecordingSettings() {
        openPrivacySettings(anchor: "Privacy_ScreenCapture")
    }

    private static func openPrivacySettings(anchor: String) {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(anchor)") else {
            return
        }
        NSWorkspace.shared.open(url)
    }
}
