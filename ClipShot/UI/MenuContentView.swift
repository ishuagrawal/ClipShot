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
                    Text("Browser extension bridge")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Divider()

            VStack(alignment: .leading, spacing: 4) {
                Text("Screen capture")
                    .font(.subheadline.weight(.semibold))
                Text("Press Control Shift 5, then drag an exact region or click a window.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Divider()

            VStack(alignment: .leading, spacing: 4) {
                Text("Web DOM capture")
                    .font(.subheadline.weight(.semibold))
                Text("Use the Arc/Chrome extension command from the browser.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("ClipShot opens the selected page region in the desktop editor.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Divider()

            if let status = appState.lastCaptureStatus {
                Label(status, systemImage: "circle.fill")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Label("Starting DOM bridge", systemImage: "circle")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Divider()

            HStack {
                Spacer()

                Button("Quit") {
                    NSApplication.shared.terminate(nil)
                }
            }
        }
        .padding(16)
        .frame(width: 320)
    }
}
