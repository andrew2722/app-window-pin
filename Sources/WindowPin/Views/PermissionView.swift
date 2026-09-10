import SwiftUI

/// Shown instead of the controls until the app is trusted for Accessibility.
///
/// The button prompts once and then just opens System Settings, so the user is
/// never nagged by repeated system dialogs.
struct PermissionView: View {
    @Environment(AppModel.self) private var model

    private static let steps = [
        "Open System Settings",
        "Go to Privacy & Security › Accessibility",
        "Turn on Window Pin",
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.l) {
            HStack(spacing: Theme.Space.m) {
                IconTile(symbol: "lock.shield.fill", tint: Theme.brand, size: 38)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Accessibility access needed")
                        .font(.headline)
                    Text("Required to move and resize other apps' windows.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            VStack(alignment: .leading, spacing: Theme.Space.s) {
                ForEach(Array(Self.steps.enumerated()), id: \.offset) { index, step in
                    HStack(alignment: .firstTextBaseline, spacing: Theme.Space.s) {
                        Text("\(index + 1)")
                            .font(.caption2.weight(.bold).monospacedDigit())
                            .foregroundStyle(Theme.brand)
                            .frame(width: 18, height: 18)
                            .background(Theme.brand.opacity(0.15), in: .circle)
                        Text(step)
                            .font(.caption)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .padding(Theme.Space.m)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.surface, in: .rect(cornerRadius: Theme.Radius.card))
            .accessibilityElement(children: .combine)

            HStack(spacing: Theme.Space.s) {
                Button("Open Settings") {
                    model.accessibility.requestPermission()
                    model.accessibility.openSettings()
                }
                .buttonStyle(.borderedProminent)
                .tint(Theme.brandFill)

                Button("Recheck") { model.refresh() }
                Spacer(minLength: 0)
            }
            .controlSize(.regular)
        }
        .padding(Theme.Space.l)
        .frame(width: Theme.controlWidth)
    }
}
