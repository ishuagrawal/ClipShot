import SwiftUI

struct MenuContentView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Image(systemName: "crop")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(.blue)

                VStack(alignment: .leading, spacing: 2) {
                    Text("ClipShot")
                        .font(.headline)
                    Text("Web DOM bridge + native fallback")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Divider()

            VStack(alignment: .leading, spacing: 4) {
                Text("Web DOM capture")
                    .font(.subheadline.weight(.semibold))
                Text("Use the Arc/Chrome extension command: Control Shift 5.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Divider()

            PermissionStatusRow(
                title: "Screen Recording",
                isGranted: appState.hasScreenRecordingPermission,
                hint: "Only needed for native fallback capture.",
                requestAction: appState.requestScreenRecordingPermission,
                settingsAction: appState.openScreenRecordingSettings
            )

            PermissionStatusRow(
                title: "Accessibility",
                isGranted: appState.hasAccessibilityPermission,
                hint: "Only needed for native fallback capture.",
                requestAction: appState.requestAccessibilityPermission,
                settingsAction: appState.openAccessibilitySettings
            )

            if let status = appState.lastCaptureStatus {
                Text(status)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Divider()

            Button {
                appState.startCapture()
            } label: {
                Label("Native Fallback Capture", systemImage: "viewfinder")
            }
            .keyboardShortcut("5", modifiers: [.command, .option, .control])

            HStack {
                Button {
                    appState.refreshPermissions()
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }

                Spacer()

                Button("Quit") {
                    NSApplication.shared.terminate(nil)
                }
            }
        }
        .padding(16)
        .frame(width: 320)
        .onAppear {
            appState.refreshPermissions()
        }
    }
}
