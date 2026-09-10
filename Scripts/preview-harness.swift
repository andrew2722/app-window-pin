import AppKit
import SwiftUI

// Renders the interface to PNGs so a design change can be looked at instead of
// imagined. Compiled by Scripts/preview.sh against the app's own sources, so
// what is captured here is the real view code, not a copy that can drift.
//
// The app's own @main is excluded from that compile; this file supplies one.

/// A borderless window refuses key status by default, and AppKit renders
/// prominent buttons and selected segments in an inactive grey whenever their
/// window is not key — so captures from a plain borderless window would show
/// every primary action washed out.
private final class CapturableWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

/// Stand-in windows, because the harness is not trusted for Accessibility and
/// so the real discovery service would hand back an empty list.
@MainActor
private enum Mock {
    static let windows: [(app: String, title: String, size: CGSize)] = [
        ("Google Chrome", "Gmail — Inbox (12)", CGSize(width: 1440, height: 900)),
        ("Visual Studio Code", "PanelRootView.swift — app-floating", CGSize(width: 1280, height: 820)),
        ("Terminal", "kieuanhduc — zsh — 120×36", CGSize(width: 900, height: 600)),
        ("Notes", "Design review", CGSize(width: 640, height: 720)),
    ]
}

@MainActor
private func render<V: View>(_ view: V, width: CGFloat, scheme: ColorScheme,
                             appearance: NSAppearance.Name, to path: String) {
    // Rendered through a real window rather than ImageRenderer: ImageRenderer
    // draws SwiftUI only, and silently replaces AppKit-backed controls — a
    // segmented picker, a text field — with a "not available" placeholder,
    // which is exactly the part of a redesign that needs looking at.
    // controlActiveState is forced to .key: an off-screen capture window never
    // reports itself active, and SwiftUI greys out prominent buttons and
    // selected segments whenever it is not — which would show every primary
    // action in the wrong state.
    let hosting = NSHostingView(rootView: view.frame(width: width)
        .environment(\.colorScheme, scheme)
        .environment(\.controlActiveState, .key))
    hosting.appearance = NSAppearance(named: appearance)
    hosting.layoutSubtreeIfNeeded()
    let size = NSSize(width: width, height: hosting.fittingSize.height)
    hosting.frame = CGRect(origin: .zero, size: size)

    let window = CapturableWindow(contentRect: hosting.frame, styleMask: [.borderless],
                                  backing: .buffered, defer: false)
    window.appearance = NSAppearance(named: appearance)
    window.contentView = hosting
    // Off to the side and behind everything, so capturing does not flash a
    // window over whatever the user is doing.
    window.setFrameOrigin(NSPoint(x: -10_000, y: -10_000))
    // Key, because AppKit draws prominent buttons and selected segments in an
    // inactive grey when their window is not — which would misrepresent every
    // primary action in these captures. The window is off-screen, so nothing
    // appears over the user's work.
    window.makeKeyAndOrderFront(nil)
    NSApp.activate(ignoringOtherApps: true)

    // SwiftUI lays out on the run loop, so a body that has never been through
    // one renders empty.
    RunLoop.main.run(until: Date().addingTimeInterval(0.35))
    hosting.layoutSubtreeIfNeeded()

    guard let rep = hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds) else {
        FileHandle.standardError.write("could not allocate bitmap for \(path)\n".data(using: .utf8)!)
        return
    }
    hosting.cacheDisplay(in: hosting.bounds, to: rep)
    try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: path))
    window.orderOut(nil)
    print("\(path)  \(Int(size.width))×\(Int(size.height))pt  \(rep.pixelsWide)×\(rep.pixelsHigh)px")
}

@main
@MainActor
enum PreviewHarness {
    static func main() {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)

        let outputDirectory = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "."
        let schemes: [(String, ColorScheme, NSAppearance.Name)] = [
            ("light", .light, .aqua),
            ("dark", .dark, .darkAqua),
        ]

        for (suffix, scheme, appearanceName) in schemes {
            // Both are set: the environment drives SwiftUI's own semantic
            // colours, the appearance drives the NSColor-backed theme colours.
            NSApp.appearance = NSAppearance(named: appearanceName)

            render(PreviewScreens.controller, width: Theme.controlWidth,
                   scheme: scheme, appearance: appearanceName, to: "\(outputDirectory)/controller-\(suffix).png")
            render(PreviewScreens.permission, width: Theme.controlWidth,
                   scheme: scheme, appearance: appearanceName, to: "\(outputDirectory)/permission-\(suffix).png")
            render(PreviewScreens.panelHeader, width: Theme.controlWidth,
                   scheme: scheme, appearance: appearanceName, to: "\(outputDirectory)/panel-header-\(suffix).png")
            render(PreviewScreens.dropZone.frame(height: 260), width: 420,
                   scheme: scheme, appearance: appearanceName, to: "\(outputDirectory)/drop-zone-\(suffix).png")
        }
    }
}

/// Assembles each screen out of the presentational pieces, with the mock data
/// the live model cannot supply here.
@MainActor
private enum PreviewScreens {

    static var controller: some View {
        VStack(alignment: .leading, spacing: Theme.Space.l) {
            HStack(spacing: Theme.Space.s) {
                Text("Window Pin").font(.headline)
                Spacer(minLength: 0)
                StatePill(text: "Pinned", color: Theme.pinFill, filled: true, onFilled: Theme.onPinFill)
            }

            PanelSection("Windows") {
                IconButton(symbol: "arrow.clockwise", label: "Refresh") {}
            } content: {
                VStack(spacing: 2) {
                    ForEach(Array(Mock.windows.enumerated()), id: \.offset) { index, window in
                        MockRow(app: window.app, title: window.title,
                                size: window.size, isSelected: index == 0)
                    }
                }
                .padding(Theme.Space.xs)
                .background(Theme.surface, in: .rect(cornerRadius: Theme.Radius.card))
            }

            VStack(spacing: Theme.Space.s) {
                HStack(spacing: Theme.Space.s) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Google Chrome").font(.callout.weight(.semibold))
                        Text("Gmail — Inbox (12)").font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer(minLength: Theme.Space.xs)
                    Text(CGSize(width: 1440, height: 900).displayDescription).font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                }
                .padding(Theme.Space.m)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Theme.pin.opacity(0.12), in: .rect(cornerRadius: Theme.Radius.card))
                .overlay {
                    RoundedRectangle(cornerRadius: Theme.Radius.card)
                        .strokeBorder(Theme.pin.opacity(0.45), lineWidth: 1)
                }

                Button {} label: {
                    Label("Unpin", systemImage: "pin.slash.fill").frame(maxWidth: .infinity)
                }
                .controlSize(.large)
            }

            PanelSection("Position · Bottom Right") {
                PositionGrid(selection: .constant(.bottomRight), isEnabled: true) { _ in }
            }

            PanelSection("Size") {
                Picker("Size", selection: .constant(SizePreset.portrait)) {
                    ForEach(SizePreset.allCases) { Text($0.shortLabel).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }

            HStack {
                QuietButton(title: "Detach Controller") {}
                Spacer(minLength: 0)
                QuietButton(title: "Quit") {}
            }
        }
        .padding(Theme.Space.l)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    static var permission: some View {
        VStack(alignment: .leading, spacing: Theme.Space.l) {
            HStack(spacing: Theme.Space.m) {
                IconTile(symbol: "lock.shield.fill", tint: Theme.brand, size: 38)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Accessibility access needed").font(.headline)
                    Text("Required to move and resize other apps' windows.")
                        .font(.caption).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            VStack(alignment: .leading, spacing: Theme.Space.s) {
                ForEach(Array(["Open System Settings",
                               "Go to Privacy & Security › Accessibility",
                               "Turn on Window Pin"].enumerated()), id: \.offset) { index, step in
                    HStack(alignment: .firstTextBaseline, spacing: Theme.Space.s) {
                        Text("\(index + 1)")
                            .font(.caption2.weight(.bold).monospacedDigit())
                            .foregroundStyle(Theme.brand)
                            .frame(width: 18, height: 18)
                            .background(Theme.brand.opacity(0.15), in: .circle)
                        Text(step).font(.caption)
                    }
                }
            }
            .padding(Theme.Space.m)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.surface, in: .rect(cornerRadius: Theme.Radius.card))

            HStack(spacing: Theme.Space.s) {
                Button("Open Settings") {}
                    .buttonStyle(.borderedProminent).tint(Theme.brandFill)
                Button("Recheck") {}
                Spacer(minLength: 0)
            }
        }
        .padding(Theme.Space.l)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    static var panelHeader: some View {
        HStack(spacing: Theme.Space.m) {
            IconTile(symbol: "rectangle.on.rectangle", tint: Theme.brand)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: Theme.Space.s) {
                    Text("Floating Panel").font(.callout.weight(.semibold))
                    StatePill(text: "Mirroring", color: Theme.brandFill, filled: true, onFilled: Theme.onBrandFill)
                }
                Text("Mirroring Gmail — Inbox (12).")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer(minLength: Theme.Space.xs)
            Button("Open") {}
                .buttonStyle(.borderedProminent).tint(Theme.brandFill)
        }
        .padding(Theme.Space.l)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    static var dropZone: some View {
        VStack(spacing: Theme.Space.m) {
            IconTile(symbol: "arrow.down.doc", tint: Theme.brand, size: 52)
            VStack(spacing: Theme.Space.xs) {
                Text("Drop anything here").font(.headline)
                Text("A link, image, PDF, video or text.\nLinks stay interactive — you can click and type in them.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(Theme.Space.xl)
        .background {
            RoundedRectangle(cornerRadius: Theme.Radius.card)
                .strokeBorder(Theme.hairline, style: StrokeStyle(lineWidth: 1.5, dash: [7, 5]))
                .padding(Theme.Space.m)
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }
}

/// The picker row, fed by mock data rather than a live `WindowInfo`.
private struct MockRow: View {
    let app: String
    let title: String
    let size: CGSize
    let isSelected: Bool

    var body: some View {
        HStack(spacing: Theme.Space.s) {
            Image(systemName: "macwindow")
                .font(.system(size: 13))
                .foregroundStyle(isSelected ? AnyShapeStyle(.white) : AnyShapeStyle(.secondary))
                .frame(width: 20, height: 20)
            VStack(alignment: .leading, spacing: 0) {
                Text(app).font(.callout.weight(.medium)).lineLimit(1)
                Text(title)
                    .font(.caption)
                    .foregroundStyle(isSelected ? .white.opacity(0.9) : .secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: Theme.Space.xs)
            Text(size.displayDescription)
                .font(.caption.monospacedDigit())
                .foregroundStyle(isSelected ? .white.opacity(0.9) : .secondary)
        }
        .foregroundStyle(isSelected ? AnyShapeStyle(.white) : AnyShapeStyle(.primary))
        .padding(.horizontal, Theme.Space.s)
        .frame(height: Theme.rowHeight)
        .background(isSelected ? AnyShapeStyle(Theme.brandFill) : AnyShapeStyle(Color.clear),
                    in: .rect(cornerRadius: Theme.Radius.row))
    }
}
