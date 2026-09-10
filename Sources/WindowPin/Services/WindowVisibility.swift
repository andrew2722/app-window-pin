import CoreGraphics

/// Answers "is this window on the Desktop the user is looking at right now?".
///
/// macOS Spaces are the reason this matters. `CGWindowListCopyWindowInfo` with
/// `.optionOnScreenOnly` only reports windows on the **active** Space, and
/// ScreenCaptureKit agrees: a window it marks `isOnScreen == false` delivers
/// **zero frames**, measured repeatedly. So a window sitting on Desktop 5 simply
/// cannot be mirrored while the user is on Desktop 1 — the app has to detect
/// that and say so rather than showing a black rectangle.
@MainActor
enum WindowVisibility {
    static func isOnActiveSpace(windowID: CGWindowID) -> Bool {
        contains(windowID, in: .optionOnScreenOnly)
    }

    /// Whether the window still exists anywhere, on any Desktop.
    ///
    /// Distinguishes "moved to another Desktop" from "closed": both stop the
    /// frames, but only one of them is worth offering to switch to.
    static func exists(windowID: CGWindowID) -> Bool {
        contains(windowID, in: .optionAll)
    }

    private static func contains(_ windowID: CGWindowID, in options: CGWindowListOption) -> Bool {
        guard let raw = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else {
            return false
        }
        return raw.contains { ($0[kCGWindowNumber as String] as? CGWindowID) == windowID }
    }
}
