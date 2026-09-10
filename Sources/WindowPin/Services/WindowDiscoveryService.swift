import AppKit
import ApplicationServices
import CoreGraphics
import Observation

/// Builds the list of pinnable windows currently on screen.
///
/// Titles and frames come from the Accessibility API (which we already need
/// permission for). CoreGraphics is consulted only for window *numbers*:
/// `CGWindowListCopyWindowInfo` returns pid, bounds and number without any
/// extra permission, whereas reading `kCGWindowName` from it would additionally
/// require Screen Recording access — so we never ask it for titles.
@MainActor
@Observable
final class WindowDiscoveryService {
    private(set) var windows: [WindowInfo] = []
    private(set) var lastRefresh: Date?

    /// Rebuilds `windows`. Called on demand (menu opened, refresh tapped),
    /// never on a timer — enumerating every app is the expensive operation in
    /// this app and there is no reason to do it in the background.
    func refresh() {
        guard AXIsProcessTrusted() else {
            windows = []
            return
        }

        let ownPID = ProcessInfo.processInfo.processIdentifier
        let windowNumbers = onScreenWindowNumbersByPID()
        var discovered: [WindowInfo] = []

        for app in NSWorkspace.shared.runningApplications {
            // `.regular` excludes daemons and menu-bar-only agents, which have
            // no windows a user would want to pin.
            guard app.activationPolicy == .regular,
                  !app.isTerminated,
                  app.processIdentifier != ownPID else { continue }

            discovered.append(contentsOf: windows(of: app, windowNumbers: windowNumbers[app.processIdentifier] ?? []))
        }

        windows = discovered.sorted {
            ($0.appName.localizedCaseInsensitiveCompare($1.appName) == .orderedAscending)
                || ($0.appName == $1.appName && $0.title < $1.title)
        }
        lastRefresh = Date()
        Log.discovery.info("Discovered \(self.windows.count, privacy: .public) window(s)")
    }

    #if PREVIEW
    /// Fills the list for the preview harness, which is not trusted for
    /// Accessibility and would otherwise render every screen empty.
    func seedForPreview(_ windows: [WindowInfo]) {
        self.windows = windows
    }
    #endif

    /// Finds a window matching a previously pinned one after its app restarted.
    /// Title is the only durable hint we have, so an exact title match wins and
    /// a single-window app is accepted as an unambiguous fallback.
    func findWindow(bundleIdentifier: String?, title: String) -> WindowInfo? {
        guard let bundleIdentifier else { return nil }
        let candidates = windows.filter { $0.bundleIdentifier == bundleIdentifier }
        if let exact = candidates.first(where: { $0.title == title }) { return exact }
        return candidates.count == 1 ? candidates.first : nil
    }

    // MARK: - Accessibility enumeration

    private func windows(of app: NSRunningApplication, windowNumbers: [(number: CGWindowID, frame: CGRect)]) -> [WindowInfo] {
        let pid = app.processIdentifier
        let axApp = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(axApp, 0.35)

        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(axApp, kAXWindowsAttribute as CFString, &value) == .success,
              let axWindows = value as? [AXUIElement] else {
            return []
        }

        let appName = app.localizedName ?? "Unknown app"
        var result: [WindowInfo] = []
        var unmatched = windowNumbers

        for element in axWindows {
            let handle = AXWindowHandle(element: element, pid: pid)

            // Filters run cheapest-and-most-selective first, since each one is
            // a round trip to the owning application.
            //
            // Role excludes things that are exposed alongside real windows but
            // are not windows — the Finder desktop is an `AXScrollArea`, and
            // sheets, drawers and popovers have roles of their own.
            guard handle.role() == (kAXWindowRole as String) else { continue }

            // Standard windows only; floating tool palettes belong to their app.
            let subrole = handle.subrole()
            guard subrole == nil || subrole == (kAXStandardWindowSubrole as String) else { continue }

            // If the app will not let us set a position, listing the window
            // would be a promise we cannot keep.
            guard handle.isPositionSettable() else { continue }
            guard !handle.isMinimized(), let frame = handle.frame(), frame.width > 1, frame.height > 1 else { continue }

            let match = Self.bestMatchIndex(for: frame, in: unmatched)
            let number = match.map { unmatched[$0].number }
            if let match { unmatched.remove(at: match) }

            result.append(
                WindowInfo(
                    handle: handle,
                    pid: pid,
                    bundleIdentifier: app.bundleIdentifier,
                    appName: appName,
                    title: handle.title() ?? "",
                    windowNumber: number,
                    frame: frame
                )
            )
        }
        return result
    }

    // MARK: - CoreGraphics window numbers

    /// On-screen window numbers with their AppKit frames, grouped by owning pid.
    private func onScreenWindowNumbersByPID() -> [pid_t: [(number: CGWindowID, frame: CGRect)]] {
        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        guard let raw = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else {
            return [:]
        }

        var grouped: [pid_t: [(number: CGWindowID, frame: CGRect)]] = [:]
        for entry in raw {
            // Layer 0 is the normal window layer; anything else is a panel,
            // menu, or system overlay.
            guard (entry[kCGWindowLayer as String] as? Int) == 0,
                  let pid = entry[kCGWindowOwnerPID as String] as? pid_t,
                  let number = entry[kCGWindowNumber as String] as? CGWindowID,
                  let boundsDict = entry[kCGWindowBounds as String] as? [String: Any],
                  let axFrame = CGRect(dictionaryRepresentation: boundsDict as CFDictionary) else { continue }

            grouped[pid, default: []].append((number, WindowGeometry.appKitRect(fromAX: axFrame)))
        }
        return grouped
    }

    /// Pairs an Accessibility window with a CoreGraphics entry by frame.
    /// Frames from the two APIs agree to the pixel for normal windows, so a
    /// small tolerance is enough and avoids mispairing same-size windows.
    private static func bestMatchIndex(for frame: CGRect,
                                       in candidates: [(number: CGWindowID, frame: CGRect)]) -> Int? {
        candidates.firstIndex { WindowGeometry.isApproximatelyEqual($0.frame, frame, tolerance: 2) }
    }
}
