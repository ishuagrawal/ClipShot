import SwiftUI

struct PermissionStatusRow: View {
    let title: String
    let isGranted: Bool
    var hint: String?
    let requestAction: () -> Void
    let settingsAction: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: isGranted ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                .foregroundStyle(isGranted ? .green : .orange)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline)
                Text(isGranted ? "Granted" : "Check System Settings")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if !isGranted, let hint {
                    Text(hint)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Spacer()

            if isGranted {
                Button {
                    settingsAction()
                } label: {
                    Image(systemName: "gearshape")
                }
                .buttonStyle(.borderless)
                .help("Open System Settings")
            } else {
                Button("Allow") {
                    requestAction()
                    settingsAction()
                }
            }
        }
    }
}
