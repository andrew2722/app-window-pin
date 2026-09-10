import SwiftUI

/// Shown instead of the controls until the app is trusted for Accessibility.
///
/// The button prompts once and then just opens System Settings, so the user is
/// never nagged by repeated system dialogs.
struct PermissionView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Accessibility access needed", systemImage: "lock.shield")
                .font(.headline)

            Text("Window Pin needs Accessibility access to move and resize windows from other applications.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: 4) {
                Text("System Settings")
                Text("→ Privacy & Security")
                Text("→ Accessibility")
                Text("→ enable Window Pin")
            }
            .font(.caption)
            .foregroundStyle(.secondary)

            HStack {
                Button("Open Accessibility Settings") {
                    model.accessibility.requestPermission()
                    model.accessibility.openSettings()
                }
                .buttonStyle(.borderedProminent)

                Button("Recheck") { model.refresh() }
            }
        }
        .padding(16)
    }
}
