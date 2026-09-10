import SwiftUI

/// Scrollable list of every pinnable window, one row per window.
struct WindowPickerView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Windows")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Button {
                    model.refresh()
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.borderless)
                .help("Refresh window list")
            }

            if model.discovery.windows.isEmpty {
                Text("No windows found. Open an app with a visible window, then refresh.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 8)
            } else {
                ScrollView {
                    LazyVStack(spacing: 2) {
                        ForEach(model.discovery.windows) { window in
                            WindowRow(window: window, isSelected: window.id == model.selectedWindowID)
                                .contentShape(.rect)
                                .onTapGesture { model.select(window) }
                        }
                    }
                }
                .frame(height: 168)
            }
        }
    }
}

private struct WindowRow: View {
    let window: WindowInfo
    let isSelected: Bool

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            VStack(alignment: .leading, spacing: 1) {
                Text(window.appName)
                    .font(.callout.weight(.medium))
                    .lineLimit(1)
                Text(window.displayTitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 4)
            VStack(alignment: .trailing, spacing: 1) {
                Text(window.sizeDescription)
                    .font(.caption.monospacedDigit())
                Text(window.positionDescription)
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(isSelected ? Color.accentColor.opacity(0.18) : Color.clear,
                    in: .rect(cornerRadius: 6))
        .help("PID \(window.pid)" + (window.windowNumber.map { " · window #\($0)" } ?? ""))
    }
}
