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
        .frame(width: Theme.controlWidth)
    }

    /// The panel half, as a single card rather than a heading with a paragraph
    /// under it — the user's decision here is only ever "open it or not".
    private var panelSection: some View {
        HStack(spacing: Theme.Space.m) {
            IconTile(symbol: "rectangle.on.rectangle", tint: Theme.brand)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: Theme.Space.s) {
                    Text("Floating Panel")
                        .font(.callout.weight(.semibold))
                    if panelModel.mirror.isMirroring {
                        StatePill(text: "Mirroring", color: Theme.brandFill, filled: true, onFilled: Theme.onBrandFill)
                    }
                }
                Text(statusText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: Theme.Space.xs)

            Button("Open") { onToggleContentPanel() }
                .buttonStyle(.borderedProminent)
                .tint(Theme.brandFill)
                .controlSize(.regular)
        }
        .padding(Theme.Space.l)
    }

    private var statusText: String {
        if panelModel.mirror.isMirroring {
            return "Mirroring \(panelModel.content.label)."
        }
        if panelModel.content.isEmpty {
            return "Drop a link, image, PDF, video or text. Stays above other apps."
        }
        return "Showing \(panelModel.content.label)."
    }
}

/// A rounded tile holding a symbol — used wherever a section needs a visual
/// anchor at its leading edge.
struct IconTile: View {
    let symbol: String
    let tint: Color
    var size: CGFloat = 34

    var body: some View {
        RoundedRectangle(cornerRadius: size * 0.28)
            .fill(tint.opacity(0.15))
            .frame(width: size, height: size)
            .overlay {
                Image(systemName: symbol)
                    .font(.system(size: size * 0.44, weight: .medium))
                    .foregroundStyle(tint)
            }
            .accessibilityHidden(true)
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
