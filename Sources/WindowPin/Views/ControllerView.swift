import SwiftUI

/// The compact controller: pick a window, pin it, snap it.
///
/// Used both as the menu bar popover content and as the content of the
/// detachable floating panel, which is why the panel button is optional.
struct ControllerView: View {
    /// Hidden when this view *is* the floating panel.
    var showsFloatingPanelButton = true
    var onToggleFloatingPanel: () -> Void = {}

    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header

            if case .unavailable(let appName, let title) = model.pinService.state {
                banner(
                    icon: "exclamationmark.triangle",
                    tint: .orange,
                    title: "Window unavailable",
                    message: "\(appName) — \(title.isEmpty ? "window closed" : title)"
                ) {
                    Button("Dismiss") { model.dismissUnavailable() }
                }
            }

            if let restorable = model.restorablePin {
                banner(
                    icon: "clock.arrow.circlepath",
                    tint: .accentColor,
                    title: "Previous pin found",
                    message: "\(restorable.appName) at \(Int(restorable.frame.width)) x \(Int(restorable.frame.height))"
                ) {
                    Button("Restore") { model.restoreSavedPin() }
                    Button("Discard") { model.discardSavedPin() }
                }
            }

            WindowPickerView()

            Divider()

            summary
            pinButton

            Divider()

            presets

            Divider()

            footer
        }
        .padding(14)
        .frame(width: 320)
        .onAppear { model.refresh() }
    }

    // MARK: - Sections

    private var header: some View {
        HStack {
            Label("Window Pin", systemImage: model.pinService.state.isPinned ? "pin.fill" : "pin")
                .font(.headline)
            Spacer()
            if model.pinService.isPollingFallback {
                Image(systemName: "timer")
                    .foregroundStyle(.secondary)
                    .help("This app does not send window events; Window Pin is polling instead.")
            }
        }
    }

    @ViewBuilder
    private var summary: some View {
        if let appName = model.activeAppName {
            VStack(alignment: .leading, spacing: 2) {
                Text(appName)
                    .font(.callout.weight(.semibold))
                Text(model.activeTitle.flatMap { $0.isEmpty ? nil : $0 } ?? "Untitled window")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                if let frame = model.activeFrame {
                    Text("Position: \(model.position?.label ?? "Manual")   Size: \(Int(frame.width)) x \(Int(frame.height))")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
        } else {
            Text("Select a window above.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var pinButton: some View {
        if model.pinService.state.isPinned {
            Button("Unpin", systemImage: "pin.slash") { model.unpin() }
                .frame(maxWidth: .infinity)
        } else {
            Button("Pin Window", systemImage: "pin") { model.pin() }
                .buttonStyle(.borderedProminent)
                .disabled(!model.canPin)
                .frame(maxWidth: .infinity)
        }
    }

    private var presets: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Presets")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            HStack(spacing: 4) {
                ForEach(PositionPreset.allCases) { preset in
                    Button(preset.shortLabel) { model.applySnap(position: preset) }
                        .buttonStyle(.bordered)
                        .tint(model.position == preset ? .accentColor : nil)
                        .help(preset.label)
                }
            }

            HStack(spacing: 4) {
                ForEach(SizePreset.allCases) { preset in
                    Button(preset.label) { model.applySnap(size: preset) }
                        .buttonStyle(.bordered)
                        .tint(model.size == preset ? .accentColor : nil)
                }
            }
            .font(.caption)

            if model.size == .custom {
                customSizeFields
            }
        }
        .disabled(model.activeFrame == nil)
    }

    private var customSizeFields: some View {
        HStack(spacing: 6) {
            TextField("Width", value: dimension(\.width), format: .number.precision(.fractionLength(0)))
                .frame(width: 64)
            Text("x").foregroundStyle(.secondary)
            TextField("Height", value: dimension(\.height), format: .number.precision(.fractionLength(0)))
                .frame(width: 64)
            Button("Apply") { model.applySnap(size: .custom) }
                .disabled(model.position == nil)
                .help(model.position == nil ? "Choose a position preset first" : "Resize to these dimensions")
        }
        .textFieldStyle(.roundedBorder)
        .font(.caption.monospacedDigit())
    }

    /// Bridges a `CGFloat` component of the custom size to the `Double` that
    /// `TextField`'s number format style works with, and refuses zero or
    /// negative sizes that no window could adopt.
    private func dimension(_ keyPath: WritableKeyPath<CGSize, CGFloat>) -> Binding<Double> {
        Binding(
            get: { Double(model.customSize[keyPath: keyPath]) },
            set: { model.customSize[keyPath: keyPath] = max(1, CGFloat($0)) }
        )
    }

    private var footer: some View {
        HStack {
            if showsFloatingPanelButton {
                Button("Show Controller") { onToggleFloatingPanel() }
                    .buttonStyle(.link)
            }
            Spacer()
            Button("Quit") { NSApplication.shared.terminate(nil) }
                .buttonStyle(.link)
        }
        .font(.caption)
    }

    @ViewBuilder
    private func banner<Actions: View>(icon: String,
                                       tint: Color,
                                       title: String,
                                       message: String,
                                       @ViewBuilder actions: () -> Actions) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Label(title, systemImage: icon)
                .font(.caption.weight(.semibold))
                .foregroundStyle(tint)
            Text(message)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
            HStack(spacing: 6) { actions() }
                .font(.caption)
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(tint.opacity(0.12), in: .rect(cornerRadius: 8))
    }
}
