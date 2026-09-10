import AppKit

/// Application icons for the window picker, looked up by process id.
///
/// A window row without its app's icon is just two lines of grey text, and the
/// icon is what the eye actually scans for when picking "the Chrome window".
///
/// Cached because the picker rebuilds its rows on every refresh and on every
/// selection change, and hitting `NSRunningApplication` for each row each time
/// is wasted work for something that never changes while an app is running.
@MainActor
enum AppIcon {
    private static var cache: [pid_t: NSImage] = [:]

    static func forProcess(_ pid: pid_t) -> NSImage? {
        if let cached = cache[pid] { return cached }
        guard let icon = NSRunningApplication(processIdentifier: pid)?.icon else { return nil }
        cache[pid] = icon
        return icon
    }

    /// Drops icons for applications that have quit, so the cache cannot grow
    /// without bound across a long-running session.
    static func prune(keeping livePIDs: Set<pid_t>) {
        cache = cache.filter { livePIDs.contains($0.key) }
    }
}
