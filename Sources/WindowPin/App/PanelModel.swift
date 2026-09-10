import AppKit
import Observation
import ScreenCaptureKit

/// State for the floating content panel.
///
/// Independent of the window-pinning half of the app: candidates for mirroring
/// come from ScreenCaptureKit rather than the Accessibility API, so the panel
/// works even when Accessibility permission has not been granted.
@MainActor
@Observable
final class PanelModel {
    private(set) var content: PanelContent = .empty
    /// True while a drag is hovering the panel, for the drop highlight.
    var isDropHighlighted = false

    let mirror = WindowMirrorService()
    let screenRecording = ScreenRecordingService()
    /// Created once and reused, so back/forward history survives dropping a
    /// second link into the panel.
    let web = WebSession()

    /// Set by the panel window so it can match the mirrored window's shape.
    /// `nil` means "no particular shape wanted".
    @ObservationIgnored var onAspectRatio: ((CGSize?) -> Void)?

    /// Browsers get listed first after a URL drop, since a dropped link almost
    /// always came from one.
    private static let browserBundlePrefixes = [
        "com.google.chrome", "com.apple.safari", "org.mozilla.firefox",
        "company.thebrowser", "com.microsoft.edgemac", "com.brave.browser",
        "com.operasoftware", "com.vivaldi", "ai.perplexity"
    ]

    // MARK: - Drops

    func accept(providers: [NSItemProvider]) {
        Task {
            guard let resolved = await DropIntakeService.content(from: providers) else {
                Log.panel.notice("Dropped item had no representation the panel can show")
                return
            }
            switch resolved {
            case .web(let url):
                await openWeb(url)
            default:
                await stopMirroring()
                content = resolved
                onAspectRatio?(nil)
                Log.panel.info("Panel showing \(resolved.label, privacy: .public)")
            }
        }
    }

    // MARK: - Web

    /// Opens `url` in the panel's own web view, where the page is fully
    /// interactive — unlike a mirror, which can only show pixels.
    func openWeb(_ url: URL) async {
        await stopMirroring()
        web.load(url)
        content = .web(url)
        // A web page has no natural aspect ratio to honour.
        onAspectRatio?(nil)
        Log.panel.info("Panel opened \(url.host() ?? "page", privacy: .public)")
    }

    /// Loads whatever is typed in the address field.
    func submitAddress() async {
        guard let url = WebSession.resolve(web.addressText) else { return }
        await openWeb(url)
    }

    // MARK: - Mirroring

    /// Lists mirrorable windows and shows the picker.
    func presentWindowChooser(droppedURL: URL? = nil) async {
        guard screenRecording.refresh() else {
            screenRecording.request()
            content = .chooseWindow(candidates: [], droppedURL: droppedURL)
            return
        }
        let candidates = await availableWindows(preferBrowsers: droppedURL != nil)
        content = .chooseWindow(candidates: candidates, droppedURL: droppedURL)
    }

    /// Starts mirroring and lets the result speak for itself.
    ///
    /// Whether a window on another Desktop can be captured is decided by macOS,
    /// not by us — so the stream is always attempted and the panel reports what
    /// actually happens. If frames arrive, it works; if none do, the panel says
    /// the window is not on this Desktop and offers to switch to it.
    func mirror(_ window: MirroredWindow) async {
        await mirror.start(window)
        if mirror.errorMessage == nil {
            content = .mirror(window)
            onAspectRatio?(window.size)
        }
    }

    /// Brings `window` onto the Desktop the user is viewing, then mirrors it.
    ///
    /// There is no public API to move a window to the current Desktop, so this
    /// goes the other way: switch to where the window already is.
    func reveal(_ window: MirroredWindow) async {
        MirrorInputForwarder.reveal(windowID: window.windowID, pid: window.pid,
                                    title: window.title, size: window.size)
        // Wait for the Space switch before deciding whether it worked.
        for _ in 0..<20 {
            do { try await Task.sleep(for: .milliseconds(250)) } catch { return }
            if WindowVisibility.isOnActiveSpace(windowID: window.windowID) { break }
        }
        guard WindowVisibility.isOnActiveSpace(windowID: window.windowID) else {
            Log.panel.notice("Could not bring \(window.appName, privacy: .public)'s window into view")
            return
        }
        await mirror(window)
    }

    /// Brings the mirrored window forward so the user can interact with it
    /// directly. Synthetic clicks cannot be delivered into another app, so this
    /// is what the panel offers instead of pretending otherwise.
    func goToMirroredWindow() {
        guard let window = mirror.mirrored else { return }
        MirrorInputForwarder.bringForward(windowID: window.windowID, pid: window.pid)
    }

    func clear() async {
        await stopMirroring()
        content = .empty
        onAspectRatio?(nil)
    }

    private func stopMirroring() async {
        if mirror.isMirroring { await mirror.stop() }
    }

    private static func isBrowser(_ window: SCWindow) -> Bool {
        let bundleID = (window.owningApplication?.bundleIdentifier ?? "").lowercased()
        return browserBundlePrefixes.contains { bundleID.hasPrefix($0) }
    }

    /// Windows ScreenCaptureKit is willing to hand us, minus our own and minus
    /// the untitled scratch windows most apps keep around.
    private func availableWindows(preferBrowsers: Bool) async -> [MirroredWindow] {
        do {
            // `onScreenWindowsOnly: false` so windows on other Desktops are
            // listed rather than silently missing; each one is tagged below and
            // the UI explains why it cannot be mirrored from here.
            let content = try await SCShareableContent.excludingDesktopWindows(
                true,
                onScreenWindowsOnly: false
            )
            let ownPID = ProcessInfo.processInfo.processIdentifier
            let windows = content.windows.filter { window in
                guard let app = window.owningApplication, app.processID != ownPID else { return false }
                guard window.frame.width > 80, window.frame.height > 80 else { return false }
                // Layer 0 is the ordinary window layer. Now that off-screen
                // windows are listed too, this is what keeps Spotlight, the
                // Notification Centre and floating tool panels out of the list.
                guard window.windowLayer == 0 else { return false }
                return !(window.title ?? "").isEmpty
            }

            let mapped = windows.map { window in
                (window: window, isBrowser: Self.isBrowser(window))
            }

            let ordered = mapped.sorted { lhs, rhs in
                // Windows you can actually mirror right now come first.
                if lhs.window.isOnScreen != rhs.window.isOnScreen { return lhs.window.isOnScreen }
                if preferBrowsers, lhs.isBrowser != rhs.isBrowser { return lhs.isBrowser }
                let lhsName = lhs.window.owningApplication?.applicationName ?? ""
                let rhsName = rhs.window.owningApplication?.applicationName ?? ""
                if lhsName != rhsName { return lhsName.localizedCaseInsensitiveCompare(rhsName) == .orderedAscending }
                return (lhs.window.title ?? "") < (rhs.window.title ?? "")
            }

            return ordered.map {
                MirroredWindow(
                    windowID: $0.window.windowID,
                    pid: $0.window.owningApplication?.processID ?? 0,
                    appName: $0.window.owningApplication?.applicationName ?? "Unknown app",
                    title: $0.window.title ?? "",
                    size: $0.window.frame.size,
                    isOnActiveSpace: $0.window.isOnScreen
                )
            }
        } catch {
            Log.panel.error("Could not list windows: \(error.localizedDescription, privacy: .public)")
            return []
        }
    }
}
