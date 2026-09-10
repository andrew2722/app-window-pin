import AppKit
import ApplicationServices
import CoreGraphics

/// Sends synthesised input from the mirror panel back to the mirrored window.
///
/// ScreenCaptureKit is a one-way pipe — it hands over pixels and nothing else —
/// so interaction has to be rebuilt with `CGEvent`. Two behaviours were measured
/// rather than assumed, and they differ in a way that shapes the whole feature:
///
/// - **Keyboard events reach an app that is not active.** `postToPid` delivers
///   them to that process's key window, so the panel can drive playback without
///   taking focus away from whatever the user is actually working in.
/// - **Mouse events do not, at all.** A synthesised mouse event carries no
///   window number; tagging it with `mouseEventWindowUnderMousePointer` does not
///   help, and neither does bringing the app to the front first — measured with
///   the app frontmost, active, and the click at verified coordinates, AppKit
///   still discarded it. So the panel does not pretend to forward clicks. A
///   click asks to jump to the real window instead, which is a thing that works.
@MainActor
enum MirrorInputForwarder {
    // MARK: - Keyboard

    /// Forwards a key press. Works with the mirrored app in the background.
    static func send(key event: NSEvent, to pid: pid_t) {
        guard let source = CGEventSource(stateID: .hidSystemState) else { return }
        let keyDown = event.type == .keyDown
        guard let synthetic = CGEvent(keyboardEventSource: source,
                                      virtualKey: CGKeyCode(event.keyCode),
                                      keyDown: keyDown) else { return }
        synthetic.flags = CGEventFlags(rawValue: UInt64(event.modifierFlags.rawValue))
        synthetic.postToPid(pid)
    }

    // MARK: - Jumping to the real window

    /// Brings the mirrored window forward so the user can interact with it
    /// directly — the honest answer to "let me click inside the mirror".
    ///
    /// `NSRunningApplication.activate()` is tried first but macOS refuses
    /// cross-app activation from an app that is not frontmost (measured
    /// returning `false`), so LaunchServices is the fallback that macOS honours.
    static func bringForward(windowID: CGWindowID, pid: pid_t) {
        raiseWindow(windowID: windowID, pid: pid)
        guard let app = NSRunningApplication(processIdentifier: pid) else { return }
        if app.activate() { return }
        guard let url = app.bundleURL else { return }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        Task { @MainActor in
            _ = try? await NSWorkspace.shared.openApplication(at: url, configuration: configuration)
        }
    }

    /// Makes a window visible on the Desktop the user is looking at.
    ///
    /// Two different things stop a window being here: it lives on another
    /// Desktop, or it is minimised. Activating the app handles the first
    /// (macOS switches Space), un-minimising handles the second. Both are
    /// attempted because the public APIs cannot cheaply tell the two apart.
    static func reveal(windowID: CGWindowID, pid: pid_t, title: String, size: CGSize) {
        // Un-minimising is the only part `bringForward` cannot do; it already
        // raises the window itself, so do not repeat that here.
        minimizedHandle(title: title, size: size, pid: pid)?.unminimize()
        bringForward(windowID: windowID, pid: pid)
    }

    /// Frame matching fails for a minimised window, so fall back to the title —
    /// but only among windows that are actually minimised, and preferring the
    /// closest size. Titles repeat constantly (two "Untitled" windows, two tabs
    /// of the same page), and un-minimising the wrong one would leave the real
    /// window hidden while appearing to have worked.
    private static func minimizedHandle(title: String, size: CGSize, pid: pid_t) -> AXWindowHandle? {
        guard AXIsProcessTrusted(), !title.isEmpty else { return nil }
        let axApp = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(axApp, 0.35)
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(axApp, kAXWindowsAttribute as CFString, &value) == .success,
              let windows = value as? [AXUIElement] else { return nil }

        let candidates = windows
            .map { AXWindowHandle(element: $0, pid: pid) }
            .filter { $0.isMinimized() && $0.title() == title }
        if candidates.count > 1 {
            Log.mirror.debug("\(candidates.count, privacy: .public) minimised windows share this title; matching on size")
        }
        return candidates.min { lhs, rhs in
            distance(lhs.frame()?.size, size) < distance(rhs.frame()?.size, size)
        }
    }

    private static func distance(_ candidate: CGSize?, _ wanted: CGSize) -> CGFloat {
        guard let candidate else { return .greatestFiniteMagnitude }
        return abs(candidate.width - wanted.width) + abs(candidate.height - wanted.height)
    }

    /// Raises the specific window within its app, so activating that app lands
    /// on the mirrored window rather than whichever one it used last.
    private static func raiseWindow(windowID: CGWindowID, pid: pid_t) {
        guard let handle = axHandle(for: windowID, pid: pid) else { return }
        handle.makeMain()
    }

    // MARK: - Window targeting

    /// Makes `windowID` its application's main window *without* activating the
    /// app, so forwarded keys land on the window being mirrored rather than
    /// whichever one that app happened to use last.
    ///
    /// Best-effort: needs Accessibility permission and cooperation from the app.
    static func focusWithoutActivating(windowID: CGWindowID, pid: pid_t) {
        axHandle(for: windowID, pid: pid)?.makeMain()
    }

    /// Finds the Accessibility handle for a CoreGraphics window.
    ///
    /// The two APIs share no identifier, so they are matched on frame — which
    /// is why this is best-effort and needs Accessibility permission.
    private static func axHandle(for windowID: CGWindowID, pid: pid_t) -> AXWindowHandle? {
        guard AXIsProcessTrusted(), let frame = currentFrame(of: windowID) else { return nil }

        let axApp = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(axApp, 0.35)

        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(axApp, kAXWindowsAttribute as CFString, &value) == .success,
              let windows = value as? [AXUIElement] else { return nil }

        let appKitFrame = WindowGeometry.appKitRect(fromAX: frame)
        return windows.lazy
            .map { AXWindowHandle(element: $0, pid: pid) }
            .first { handle in
                guard let candidate = handle.frame() else { return false }
                return WindowGeometry.isApproximatelyEqual(candidate, appKitFrame, tolerance: 4)
            }
    }

    /// Current bounds of a window in CoreGraphics coordinates (top-left origin).
    /// Read per event because the mirrored window can be moved at any time.
    private static func currentFrame(of windowID: CGWindowID) -> CGRect? {
        guard let raw = CGWindowListCopyWindowInfo([.optionIncludingWindow], windowID) as? [[String: Any]],
              let entry = raw.first,
              let bounds = entry[kCGWindowBounds as String] as? [String: Any],
              let frame = CGRect(dictionaryRepresentation: bounds as CFDictionary) else { return nil }
        return frame
    }
}
