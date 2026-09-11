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

    /// Absent in the preview harness, and in a build with no update feed —
    /// the optional form of `@Environment` returns nil instead of trapping.
    @Environment(UpdateService.self) private var updates: UpdateService?

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.l) {
            header
            notices
            WindowPickerView()
            target
            snapControls
            footer
        }
        .padding(Theme.Space.l)
        .frame(width: Theme.controlWidth)
        .animation(Theme.transition, value: model.pinService.state.isPinned)
        .animation(Theme.transition, value: model.size)
        .animation(Theme.transition, value: updates?.pendingVersion)
        .onAppear { model.refresh() }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: Theme.Space.s) {
            Text("Window Pin")
                .font(.headline)

            Spacer(minLength: 0)

            if model.pinService.isPollingFallback {
                Image(systemName: "timer")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .help("This app does not send window events; Window Pin is polling instead.")
                    .accessibilityLabel("Polling for window changes")
            }

            if model.pinService.state.isPinned {
                StatePill(text: "Pinned", color: Theme.pinFill, filled: true, onFilled: Theme.onPinFill)
            } else {
                StatePill(text: "Idle", color: .secondary, filled: false)
            }
        }
    }

    // MARK: - Notices

    @ViewBuilder
    private var notices: some View {
        if case .unavailable(let appName, let title) = model.pinService.state {
            notice(
                icon: "exclamationmark.triangle.fill",
                tint: Theme.danger,
                title: "Window unavailable",
                message: "\(appName) — \(title.isEmpty ? "window closed" : title)"
            ) {
                Button("Dismiss") { model.dismissUnavailable() }
            }
        }

        if let restorable = model.restorablePin {
            notice(
                icon: "clock.arrow.circlepath",
                tint: Theme.brand,
                title: "Previous pin found",
                message: "\(restorable.appName) at \(restorable.frame.size.displayDescription)"
            ) {
                Button("Restore") { model.restoreSavedPin() }
                    .buttonStyle(.borderedProminent)
                    .tint(Theme.brandFill)
                Button("Discard") { model.discardSavedPin() }
            }
        }
    }

    /// An inline message about something that happened, with the actions that
    /// resolve it attached — never an error the user has no way to act on.
    @ViewBuilder
    private func notice<Actions: View>(icon: String,
                                       tint: Color,
                                       title: String,
                                       message: String,
                                       @ViewBuilder actions: () -> Actions) -> some View {
        HStack(alignment: .top, spacing: Theme.Space.s) {
            Image(systemName: icon)
                .font(.callout)
                .foregroundStyle(tint)

            VStack(alignment: .leading, spacing: Theme.Space.xs) {
                Text(title)
                    .font(.caption.weight(.semibold))
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                HStack(spacing: Theme.Space.xs) { actions() }
                    .controlSize(.small)
            }
        }
        .padding(Theme.Space.m)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(tint.opacity(0.10), in: .rect(cornerRadius: Theme.Radius.card))
        .overlay {
            RoundedRectangle(cornerRadius: Theme.Radius.card)
                .strokeBorder(tint.opacity(0.30), lineWidth: 1)
        }
    }

    // MARK: - Target and the pin action

    private var target: some View {
        VStack(spacing: Theme.Space.s) {
            targetCard
            pinButton
        }
    }

    /// One line about the window the controls act on.
    ///
    /// It used to repeat the app name, title and size already shown in the
    /// highlighted row directly above — three facts twice, for about 76pt of
    /// height. What is genuinely new once a window is pinned is the frame being
    /// held, so that is what it shows now.
    @ViewBuilder
    private var targetCard: some View {
        let isPinned = model.pinService.state.isPinned

        HStack(spacing: Theme.Space.s) {
            if let appName = model.activeAppName {
                Image(systemName: isPinned ? "pin.fill" : "hand.tap")
                    .font(.caption)
                    .foregroundStyle(isPinned ? Theme.pin : Color.secondary)

                Text(isPinned ? "Holding \(appName)" : appName)
                    .font(.callout.weight(.medium))
                    .lineLimit(1)

                Spacer(minLength: Theme.Space.xs)

                if let frame = model.activeFrame {
                    // One line: wrapping here pushes the row past its own height
                    // and breaks the rhythm the rest of the panel keeps.
                    Text(isPinned ? frameSummary(frame) : frame.size.displayDescription)
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .fixedSize()
                }
            } else {
                Image(systemName: "hand.point.up.left")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                Text("Select a window above")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
            }
        }
        .padding(.horizontal, Theme.Space.m)
        .frame(height: Theme.rowHeight, alignment: .leading)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(isPinned ? AnyShapeStyle(Theme.pin.opacity(0.12)) : AnyShapeStyle(Theme.surface),
                    in: .rect(cornerRadius: Theme.Radius.card))
        .overlay {
            RoundedRectangle(cornerRadius: Theme.Radius.card)
                .strokeBorder(isPinned ? Theme.pin.opacity(0.45) : .clear, lineWidth: 1)
        }
        .accessibilityElement(children: .combine)
    }

    /// Where the window is being held, in the same words the position control
    /// uses, plus the size — the two things the pin is actually enforcing.
    private func frameSummary(_ frame: CGRect) -> String {
        let size = frame.size.displayDescription
        guard let position = model.position else { return size }
        return "\(position.label) · \(size)"
    }

    @ViewBuilder
    private var pinButton: some View {
        if model.pinService.state.isPinned {
            Button {
                model.unpin()
            } label: {
                Label("Unpin", systemImage: "pin.slash.fill")
                    .frame(maxWidth: .infinity)
            }
            // While a window is held, letting it go is the only thing this
            // screen is for, so it carries the emphasis the Pin button had.
            .buttonStyle(.borderedProminent)
            .tint(Theme.pinFill)
            .foregroundStyle(Theme.onPinFill)
            .controlSize(.large)
        } else {
            Button {
                model.pin()
            } label: {
                Label("Pin Window", systemImage: "pin.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(Theme.brandFill)
            .controlSize(.large)
            .disabled(!model.canPin)
        }
    }

    // MARK: - Snapping

    private var snapControls: some View {
        VStack(alignment: .leading, spacing: Theme.Space.m) {
            PanelSection(model.position.map { "Position · \($0.label)" } ?? "Position") {
                PositionGrid(
                    selection: .constant(model.position),
                    size: model.size,
                    referenceSize: model.size == .custom ? model.customSize
                                                         : (model.activeFrame?.size ?? .zero),
                    isEnabled: model.activeFrame != nil,
                    onSelect: { model.applySnap(position: $0) }
                )
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            PanelSection("Size") {
                Picker("Size", selection: sizeBinding) {
                    ForEach(SizePreset.allCases) { preset in
                        Text(preset.shortLabel).tag(preset)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                // Left native. A segmented control's grey selection is the
                // macOS convention, and `.tint` does not change it here — the
                // position grid is custom only because it has to show a picture
                // of the result, which no system control can do.
                // Tinted deliberately: left alone, the selected segment picks
                // up the system accent colour, so on a Mac set to (say) yellow
                // the segment and the selected window row — right above it —
                // disagree about what "selected" looks like.
                .tint(Theme.brandFill)

                if model.size == .custom {
                    customSizeFields
                        .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
        }
        .disabled(model.activeFrame == nil)
    }

    /// Choosing a segment applies the snap immediately — a size picker that
    /// needed a separate confirm step would be two clicks for one intent.
    private var sizeBinding: Binding<SizePreset> {
        Binding(
            get: { model.size },
            set: { model.applySnap(size: $0) }
        )
    }

    private var customSizeFields: some View {
        HStack(spacing: Theme.Space.s) {
            TextField("Width", value: dimension(\.width), format: .number.precision(.fractionLength(0)).grouping(.never))
                .frame(width: 68)
                .accessibilityLabel("Custom width")
            Text("×").foregroundStyle(.secondary)
            TextField("Height", value: dimension(\.height), format: .number.precision(.fractionLength(0)).grouping(.never))
                .frame(width: 68)
                .accessibilityLabel("Custom height")
            Spacer(minLength: 0)
            Button("Apply") { model.applySnap(size: .custom) }
                .disabled(model.position == nil)
                .help(model.position == nil ? "Choose a position first" : "Resize to these dimensions")
        }
        .textFieldStyle(.roundedBorder)
        .controlSize(.small)
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

    // MARK: - Footer

    private var footer: some View {
        HStack {
            if showsFloatingPanelButton {
                QuietButton(title: "Detach Controller") { onToggleFloatingPanel() }
                    .help("Open the controller in a floating window that stays put while you work")
            }

            Spacer(minLength: Theme.Space.s)
            versionLabel
            Spacer(minLength: Theme.Space.s)
            QuietButton(title: "Quit") { NSApplication.shared.terminate(nil) }
        }
    }

    /// The running version, and — where this build can update itself — the way
    /// to ask for a new one now.
    ///
    /// New versions arrive on their own, so this is not the path anyone is
    /// meant to depend on; it exists for the moment someone hears about a fix
    /// and would rather not wait for the next scheduled check. That is why it
    /// stays a version number rather than becoming a button competing with the
    /// controls above it.
    @ViewBuilder
    private var versionLabel: some View {
        if let updates, let pending = updates.pendingVersion {
            // A version was found in the background and deliberately not shown
            // over the user's work. Here it becomes the one thing in the footer
            // worth clicking.
            Button { updates.checkNow() } label: {
                Label("Update to \(pending)", systemImage: "arrow.down.circle.fill")
                    .font(.caption.weight(.medium))
            }
            .buttonStyle(.plain)
            .foregroundStyle(Theme.brand)
            .help("Install version \(pending)")
        } else if let version = Self.appVersion {
            if let updates {
                Button { updates.checkNow() } label: {
                    Text("v\(version)")
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.tertiary)
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .disabled(!updates.canCheck)
                .help("Version \(version) — click to check for updates now")
                .accessibilityLabel("Version \(version), check for updates")
            } else {
                Text("v\(version)")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.tertiary)
                    .help("The version of Window Pin you are running")
                    // Read as "Version 1.0.3", not "Version v1.0.3".
                    .accessibilityLabel("Version \(version)")
            }
        }
    }

    /// Version string from the bundle, or `nil` outside one.
    ///
    /// The preview harness is a bare executable rather than an app bundle, so
    /// there is nothing to read there — better to omit the label than to leave
    /// a gap where a version should be.
    private static var appVersion: String? {
        guard let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String,
              !version.isEmpty else { return nil }
        return version
    }
}
