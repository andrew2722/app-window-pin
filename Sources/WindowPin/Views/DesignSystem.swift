import AppKit
import SwiftUI

/// The visual vocabulary the whole interface is built from.
///
/// Before this existed, every view invented its own padding, corner radius and
/// colour at the point of use, so nothing lined up between the menu bar popover
/// and the floating panel. Anything reused more than once belongs here.
enum Theme {

    // MARK: - Colour

    /// Brand blue, taken from the app icon's plate so the interface and the
    /// icon read as one product.
    ///
    /// Split into two roles because one blue cannot do both jobs: `brand` is
    /// drawn *on* a surface (icons, borders, tinted text) and so has to be
    /// light in dark mode, while `brandFill` is a surface carrying white text
    /// and so has to stay dark enough in both modes to clear 4.5:1.
    static let brand = dynamic(light: NSColor(srgb: 0x2F62E8), dark: NSColor(srgb: 0x7FA5FF))
    static let brandFill = dynamic(light: NSColor(srgb: 0x2F62E8), dark: NSColor(srgb: 0x3366DD))
    static let onBrandFill = Color.white

    /// The pin's amber, reserved for one job: saying a window is being held.
    /// Using it for anything else would dilute the only signal the user needs
    /// to read at a glance.
    ///
    /// The filled variant flips its text colour rather than its background:
    /// amber light enough to read on a dark surface is far too light to carry
    /// white text.
    static let pin = dynamic(light: NSColor(srgb: 0xB26100), dark: NSColor(srgb: 0xFFB232))
    static let pinFill = dynamic(light: NSColor(srgb: 0xB26100), dark: NSColor(srgb: 0xFFB232))
    static let onPinFill = dynamic(light: NSColor(white: 1, alpha: 1), dark: NSColor(srgb: 0x2A1A00))

    static let danger = dynamic(light: NSColor(srgb: 0xC5303A), dark: NSColor(srgb: 0xFF6B6B))

    /// Raised surfaces (rows, cards) against the popover background.
    static let surface = dynamic(light: NSColor(srgb: 0xF2F4F8), dark: NSColor(white: 1, alpha: 0.07))
    static let surfaceHover = dynamic(light: NSColor(srgb: 0xE7EBF2), dark: NSColor(white: 1, alpha: 0.12))
    static let hairline = dynamic(light: NSColor(black: 0.10), dark: NSColor(white: 1, alpha: 0.12))

    // MARK: - Metrics

    /// 4pt rhythm. Every gap and inset in the app comes from this scale.
    enum Space {
        static let xs: CGFloat = 4
        static let s: CGFloat = 8
        static let m: CGFloat = 12
        static let l: CGFloat = 16
        static let xl: CGFloat = 20
    }

    enum Radius {
        static let control: CGFloat = 6
        static let row: CGFloat = 8
        static let card: CGFloat = 12
    }

    /// Width of the popover and of the detached controller, kept identical so
    /// the same controls do not reflow when the user pops the panel out.
    static let controlWidth: CGFloat = 340

    /// Pointer-sized hit target. The 44pt touch minimum does not apply to a
    /// mouse-driven macOS utility, but rows still need to be comfortably
    /// clickable rather than 20pt slivers.
    static let rowHeight: CGFloat = 38

    // MARK: - Motion

    /// One duration for state changes across the app, so nothing feels out of
    /// step with anything else. 180ms sits inside the 150–300ms band where a
    /// transition reads as responsive rather than sluggish.
    static let transition = Animation.easeOut(duration: 0.18)
    /// Exits run shorter than entrances — a panel that lingers on the way out
    /// feels slow even when the entrance felt fine.
    static let exit = Animation.easeIn(duration: 0.12)

    // MARK: - Helpers

    private static func dynamic(light: NSColor, dark: NSColor) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? dark : light
        })
    }
}

private extension NSColor {
    /// Hex literal in sRGB, so palette values can be written the way they were
    /// picked.
    convenience init(srgb hex: UInt32) {
        self.init(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
                  green: CGFloat((hex >> 8) & 0xFF) / 255,
                  blue: CGFloat(hex & 0xFF) / 255,
                  alpha: 1)
    }

    convenience init(black alpha: CGFloat) {
        self.init(srgbRed: 0, green: 0, blue: 0, alpha: alpha)
    }
}

// MARK: - Shared components

/// A titled group of controls.
///
/// Replaces the row of `Divider()`s the interface used to be sliced up with —
/// dividers separate things but do not say what they separate, so a popover
/// built from them reads as one long undifferentiated form.
struct PanelSection<Content: View>: View {
    let title: String
    /// Optional trailing control, e.g. a refresh button.
    var accessory: AnyView?
    @ViewBuilder var content: Content

    init(_ title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.accessory = nil
        self.content = content()
    }

    init<Accessory: View>(_ title: String,
                          @ViewBuilder accessory: () -> Accessory,
                          @ViewBuilder content: () -> Content) {
        self.title = title
        self.accessory = AnyView(accessory())
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.s) {
            HStack(spacing: Theme.Space.xs) {
                Text(title.uppercased())
                    .font(.caption2.weight(.semibold))
                    .tracking(0.6)
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
                accessory
            }
            content
        }
    }
}

/// Compact state indicator — the one thing the user should be able to read
/// without focusing on the popover at all.
struct StatePill: View {
    let text: String
    let color: Color
    /// Filled reads as "active"; outlined as "nothing happening".
    var filled: Bool
    /// Text colour when filled. Passed in rather than assumed to be white,
    /// because whether white reads on `color` depends on the colour.
    var onFilled: Color = .white

    var body: some View {
        Text(text)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(filled ? onFilled : color)
            .padding(.horizontal, Theme.Space.s)
            .padding(.vertical, 3)
            .background {
                Capsule().fill(filled ? AnyShapeStyle(color) : AnyShapeStyle(color.opacity(0.14)))
            }
            .accessibilityLabel(text)
    }
}

/// Icon-only toolbar button with the accessibility label that `.help` alone
/// does not provide — a tooltip is invisible to VoiceOver.
struct IconButton: View {
    let symbol: String
    let label: String
    var action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .medium))
                .frame(width: 24, height: 24)
                .background(Theme.surfaceHover.opacity(hovering ? 1 : 0),
                            in: .rect(cornerRadius: Theme.Radius.control))
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(Theme.transition, value: hovering)
        .help(label)
        .accessibilityLabel(label)
    }
}

/// A quiet text command, for footer actions that should not compete with the
/// primary button.
///
/// `.buttonStyle(.plain)` alone renders these as text with no hover response at
/// all, leaving them indistinguishable from labels until clicked.
struct QuietButton: View {
    let title: String
    var action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.caption)
                .foregroundStyle(hovering ? AnyShapeStyle(Theme.brand) : AnyShapeStyle(.secondary))
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(Theme.transition, value: hovering)
    }
}

/// Empty and error states, so a screen with nothing in it still explains
/// itself instead of showing a blank rectangle.
struct StatusMessage: View {
    let symbol: String
    let title: String
    var message: String?
    var tint: Color = .secondary

    var body: some View {
        VStack(spacing: Theme.Space.s) {
            Image(systemName: symbol)
                .font(.system(size: 22, weight: .light))
                .foregroundStyle(tint)
            Text(title)
                .font(.callout.weight(.medium))
                .multilineTextAlignment(.center)
            if let message {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Theme.Space.l)
    }
}
