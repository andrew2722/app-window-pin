import CoreGraphics
import Foundation

/// A window the user has pinned, together with the frame it must keep.
///
/// The frame is stored in AppKit coordinates because that is what the snap
/// presets and `NSScreen` work in; conversion to Accessibility coordinates
/// happens only at the moment the frame is written to the pinned window.
struct PinnedWindow: Identifiable {
    let id = UUID()
    let handle: AXWindowHandle
    let pid: pid_t
    let bundleIdentifier: String?
    let appName: String
    /// Title captured at pin time. Titles change (browser tabs), so this is
    /// only used for display and for re-matching after an app restart.
    var title: String
    let windowNumber: CGWindowID?
    /// The frame to hold, in AppKit coordinates.
    var frame: CGRect
    /// Display the frame was calculated against, so we can detect the monitor
    /// going away. `nil` when the display could not be identified.
    var displayUUID: String?

    var x: CGFloat { frame.origin.x }
    var y: CGFloat { frame.origin.y }
    var width: CGFloat { frame.width }
    var height: CGFloat { frame.height }

    var sizeDescription: String {
        "\(Int(frame.width.rounded())) x \(Int(frame.height.rounded()))"
    }
}

/// What the pin service is currently doing. Drives the whole controller UI.
enum PinState {
    /// Nothing pinned.
    case idle
    /// Actively holding `window` at its frame.
    case pinned(PinnedWindow)
    /// The window we were holding went away (closed, or its app quit).
    /// We stop touching it but keep the description so the UI can explain why.
    case unavailable(appName: String, title: String)

    var pinnedWindow: PinnedWindow? {
        if case .pinned(let window) = self { return window }
        return nil
    }

    var isPinned: Bool { pinnedWindow != nil }
}
