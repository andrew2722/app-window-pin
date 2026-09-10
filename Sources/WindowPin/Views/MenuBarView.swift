import SwiftUI

/// Root of the menu bar popover.
///
/// The floating panel sits above the permission gate on purpose: it only needs
/// Screen Recording, so it stays usable even when Accessibility (which only the
/// pinning half needs) has not been granted.
struct MenuBarView: View {
    var onToggleFloatingPanel: () -> Void
    var onToggleContentPanel: () -> Void

    @Environment(AppModel.self) private var model
    @Environment(PanelModel.self) private var panelModel

    var body: some View {
        VStack(spacing: 0) {
            panelSection
            Divider()
            if model.accessibility.isTrusted {
                ControllerView(showsFloatingPanelButton: true,
                               onToggleFloatingPanel: onToggleFloatingPanel)
            } else {
                PermissionView()
            }
        }
        .frame(width: 320)
    }

    private var panelSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Label("Floating Panel", systemImage: "rectangle.on.rectangle")
                    .font(.headline)
                Spacer()
                Button("Open") { onToggleContentPanel() }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
            }

            Text(statusText)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
    }

    private var statusText: String {
        if panelModel.mirror.isMirroring {
            return "Mirroring \(panelModel.content.label)."
        }
        if panelModel.content.isEmpty {
            return "Drop a link, image, PDF, video or text into it — or mirror any window. Stays above other apps."
        }
        return "Showing \(panelModel.content.label)."
    }
}

/// The menu bar icon. Reading the pin state inside a `View` body (rather than
/// in the `Scene`) is what keeps the icon updating as the state changes.
///
/// The pin is the same hand-drawn path as the app icon rather than an SF
/// Symbol, so the status item and the icon in System Settings read as one app.
struct MenuBarIcon: View {
    let model: AppModel

    var body: some View {
        Image(nsImage: PinGlyph.menuBarImage(style))
    }

    private var style: PinGlyph.Style {
        switch model.pinService.state {
        case .pinned: .filled
        case .unavailable: .unavailable
        case .idle: .outline
        }
    }
}
