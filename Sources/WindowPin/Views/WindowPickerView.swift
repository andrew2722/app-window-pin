import SwiftUI

/// Scrollable list of every pinnable window, one row per window.
struct WindowPickerView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        PanelSection("Windows") {
            IconButton(symbol: "arrow.clockwise", label: "Refresh window list") {
                model.refresh()
            }
        } content: {
            if model.discovery.windows.isEmpty {
                StatusMessage(
                    symbol: "macwindow",
                    title: "No windows found",
                    message: "Open an app with a visible window, then refresh."
                )
                .background(Theme.surface, in: .rect(cornerRadius: Theme.Radius.card))
            } else {
                ScrollView {
                    LazyVStack(spacing: 2) {
                        ForEach(model.discovery.windows) { window in
                            WindowRow(window: window, isSelected: window.id == model.selectedWindowID)
                                .onTapGesture { model.select(window) }
                        }
                    }
                    .padding(Theme.Space.xs)
                }
                // Sized to show roughly four rows: enough to scan without the
                // popover growing taller than the screen on a busy desktop.
                .frame(height: Theme.rowHeight * 4 + Theme.Space.s)
                .background(Theme.surface, in: .rect(cornerRadius: Theme.Radius.card))
            }
        }
    }
}

/// One window in the picker: who owns it, what it is, and how big it is.
private struct WindowRow: View {
    let window: WindowInfo
    let isSelected: Bool

    @State private var hovering = false

    var body: some View {
        HStack(spacing: Theme.Space.s) {
            icon

            VStack(alignment: .leading, spacing: 0) {
                Text(window.appName)
                    .font(.callout.weight(.medium))
                    .lineLimit(1)
                Text(window.displayTitle)
                    .font(.caption)
                    .foregroundStyle(isSelected ? .white.opacity(0.9) : .secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer(minLength: Theme.Space.xs)

            Text(window.sizeDescription)
                .font(.caption.monospacedDigit())
                .foregroundStyle(isSelected ? .white.opacity(0.9) : .secondary)
        }
        .foregroundStyle(isSelected ? AnyShapeStyle(.white) : AnyShapeStyle(.primary))
        .padding(.horizontal, Theme.Space.s)
        .frame(height: Theme.rowHeight)
        .background(background, in: .rect(cornerRadius: Theme.Radius.row))
        .contentShape(.rect)
        .onHover { hovering = $0 }
        .animation(Theme.transition, value: isSelected)
        .animation(Theme.transition, value: hovering)
        .help("\(window.appName) — \(window.displayTitle) at \(window.positionDescription)")
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(window.appName), \(window.displayTitle), \(window.sizeDescription)")
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }

    @ViewBuilder
    private var icon: some View {
        if let image = AppIcon.forProcess(window.pid) {
            Image(nsImage: image)
                .resizable()
                .frame(width: 20, height: 20)
        } else {
            // Keeps every row's text on the same left edge whether or not the
            // icon could be resolved.
            Image(systemName: "macwindow")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .frame(width: 20, height: 20)
        }
    }

    private var background: AnyShapeStyle {
        if isSelected { return AnyShapeStyle(Theme.brandFill) }
        if hovering { return AnyShapeStyle(Theme.surfaceHover) }
        return AnyShapeStyle(Color.clear)
    }
}
