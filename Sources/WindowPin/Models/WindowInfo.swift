import CoreGraphics
import Foundation

/// A window belonging to another application, as presented in the picker.
///
/// `handle` is the live Accessibility reference and is the primary identity —
/// `pid`, `windowNumber` and `title` are metadata used for display and for
/// re-finding the window after the owning app restarts.
struct WindowInfo: Identifiable {
    let handle: AXWindowHandle
    let pid: pid_t
    let bundleIdentifier: String?
    let appName: String
    let title: String
    /// CoreGraphics window number, when a matching on-screen window was found.
    /// Absent for windows CoreGraphics does not list (e.g. fully off-screen).
    let windowNumber: CGWindowID?
    /// Frame in AppKit coordinates.
    let frame: CGRect

    /// Keyed on the Accessibility element, which stays identical across
    /// refreshes for as long as the window exists. The CoreGraphics window
    /// number is deliberately *not* used here: matching it depends on frames
    /// agreeing, so it can be absent for one refresh while a window is being
    /// moved, which would silently drop the user's selection.
    var id: String {
        "\(pid)-\(handle.identityToken)"
    }

    var sizeDescription: String {
        frame.size.displayDescription
    }

    var positionDescription: String {
        "(\(Int(frame.origin.x.rounded())), \(Int(frame.origin.y.rounded())))"
    }

    var displayTitle: String {
        title.isEmpty ? "Untitled window" : title
    }
}
