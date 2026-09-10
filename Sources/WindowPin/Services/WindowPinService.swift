import AppKit
import Observation

/// Holds one window at a fixed frame.
///
/// The service owns the whole pinned lifecycle: writing the frame, listening
/// for the owning app moving it back, reacting to the app quitting, and
/// reacting to the display it lives on disappearing.
@MainActor
@Observable
final class WindowPinService {
    /// If an app fights us harder than this, we are in a loop rather than
    /// correcting a user action, so back off instead of burning CPU.
    private static let maxCorrectionsPerSecond = 6
    private static let backoffDuration: TimeInterval = 2

    private(set) var state: PinState = .idle
    /// Exposed so the UI can tell the user this window is being polled rather
    /// than observed.
    private(set) var isPollingFallback = false

    @ObservationIgnored private let observer = WindowObserverService()
    @ObservationIgnored private var correctionTimestamps: [Date] = []
    @ObservationIgnored private var backoffUntil: Date?
    @ObservationIgnored private var notificationTokens: [NSObjectProtocol] = []

    init() {
        observeSystemEvents()
    }

    // MARK: - Pinning

    /// Pins `window`, holding it at `frame` (AppKit coordinates). Passing `nil`
    /// pins the window exactly where it currently is.
    func pin(_ window: WindowInfo, at frame: CGRect? = nil) {
        let requested = frame ?? window.frame
        let achieved = applyFrame(requested, to: window.handle) ?? requested
        let screen = ScreenService.screen(containing: achieved)

        let pinned = PinnedWindow(
            handle: window.handle,
            pid: window.pid,
            bundleIdentifier: window.bundleIdentifier,
            appName: window.appName,
            title: window.title,
            windowNumber: window.windowNumber,
            frame: achieved,
            displayUUID: screen.flatMap(ScreenService.displayUUID(for:))
        )

        state = .pinned(pinned)
        resetCorrectionBudget()
        startObserving(pinned)
        Log.pin.info("""
            Pinned \(pinned.appName, privacy: .public) "\(pinned.title, privacy: .public)" \
            at \(String(describing: achieved), privacy: .public)
            """)
    }

    /// Stops holding the window. The window keeps whatever frame it has now.
    func unpin() {
        if let pinned = state.pinnedWindow {
            Log.pin.info("Unpinned \(pinned.appName, privacy: .public)")
        }
        observer.stop()
        isPollingFallback = false
        state = .idle
    }

    /// Clears an `.unavailable` state once the user has acknowledged it.
    func dismissUnavailable() {
        if case .unavailable = state { state = .idle }
    }

    /// Changes the frame a pinned window is held at, e.g. after a snap preset.
    func updatePinnedFrame(_ frame: CGRect) {
        guard var pinned = state.pinnedWindow else { return }
        guard let achieved = applyFrame(frame, to: pinned.handle) else {
            markUnavailable()
            return
        }
        pinned.frame = achieved
        pinned.displayUUID = ScreenService.screen(containing: achieved)
            .flatMap(ScreenService.displayUUID(for:))
        state = .pinned(pinned)
        resetCorrectionBudget()
    }

    /// Moves and resizes a window that is *not* pinned. Returns the frame the
    /// window actually settled at, or `nil` if it has gone away.
    @discardableResult
    func applyFrame(_ frame: CGRect, to handle: AXWindowHandle) -> CGRect? {
        handle.setFrame(frame)
        // Read back rather than trusting the write: apps are free to refuse or
        // adjust a frame (minimum sizes, character-cell grids, tab bars).
        guard let achieved = handle.frame() else { return nil }
        observer.acknowledgeAppliedFrame(achieved)
        if !WindowGeometry.isApproximatelyEqual(achieved, frame) {
            Log.pin.debug("""
                Window settled at \(String(describing: achieved), privacy: .public) \
                instead of \(String(describing: frame), privacy: .public)
                """)
        }
        return achieved
    }

    // MARK: - Holding the frame

    private func startObserving(_ pinned: PinnedWindow) {
        observer.start(observing: pinned.handle) { [weak self] event in
            guard let self else { return }
            switch event {
            case .frameChanged: self.restoreFrameIfNeeded()
            case .vanished: self.markUnavailable()
            }
        }
        isPollingFallback = observer.isPolling
    }

    private func restoreFrameIfNeeded() {
        guard var pinned = state.pinnedWindow else { return }
        guard let current = pinned.handle.frame() else {
            markUnavailable()
            return
        }
        guard !WindowGeometry.isApproximatelyEqual(current, pinned.frame) else { return }
        guard allowCorrection() else { return }

        guard let achieved = applyFrame(pinned.frame, to: pinned.handle) else {
            markUnavailable()
            return
        }

        // The app declined the exact frame. Adopting what it settled on is what
        // stops the two of us from correcting each other forever; the window
        // still stays put, just at the nearest frame the app will accept.
        if !WindowGeometry.isApproximatelyEqual(achieved, pinned.frame) {
            Log.pin.notice("Adopting \(pinned.appName, privacy: .public)'s adjusted frame as the pinned frame")
            pinned.frame = achieved
            state = .pinned(pinned)
        }
    }

    private func markUnavailable() {
        guard let pinned = state.pinnedWindow else { return }
        Log.pin.notice("Pinned window from \(pinned.appName, privacy: .public) is no longer available")
        observer.stop()
        isPollingFallback = false
        state = .unavailable(appName: pinned.appName, title: pinned.title)
    }

    // MARK: - Correction budget

    /// Rate-limits corrections so a misbehaving app cannot spin the CPU.
    private func allowCorrection() -> Bool {
        let now = Date()
        if let backoffUntil {
            guard now >= backoffUntil else { return false }
            self.backoffUntil = nil
            correctionTimestamps.removeAll()
        }

        correctionTimestamps = correctionTimestamps.filter { now.timeIntervalSince($0) < 1 }
        guard correctionTimestamps.count < Self.maxCorrectionsPerSecond else {
            backoffUntil = now.addingTimeInterval(Self.backoffDuration)
            Log.pin.notice("Correction rate limit hit; pausing for \(Self.backoffDuration, privacy: .public)s")
            return false
        }
        correctionTimestamps.append(now)
        return true
    }

    private func resetCorrectionBudget() {
        correctionTimestamps.removeAll()
        backoffUntil = nil
    }

    // MARK: - System events

    private func observeSystemEvents() {
        let workspaceToken = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didTerminateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            let pid = app?.processIdentifier
            MainActor.assumeIsolated {
                guard let pid else { return }
                self?.handleTermination(of: pid)
            }
        }

        let screenToken = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.handleScreenConfigurationChange()
            }
        }

        notificationTokens = [workspaceToken, screenToken]
    }

    private func handleTermination(of pid: pid_t) {
        guard let pinned = state.pinnedWindow, pinned.pid == pid else { return }
        markUnavailable()
    }

    /// Keeps a pinned window reachable when displays change.
    ///
    /// If its display was unplugged the window would otherwise be stranded in
    /// coordinates that no longer exist, so it is moved onto the primary
    /// display instead.
    private func handleScreenConfigurationChange() {
        guard var pinned = state.pinnedWindow else { return }

        let stored = pinned.displayUUID.flatMap(ScreenService.screen(withDisplayUUID:))
        // Only a pin that *had* a display and lost it needs relocating; one that
        // never resolved a display must not be dragged to the primary display
        // every time the screen configuration changes.
        let displayLost = pinned.displayUUID != nil && stored == nil
        guard let screen = stored ?? ScreenService.screen(containing: pinned.frame) else { return }

        if displayLost {
            Log.screen.notice("Pinned window's display is gone; relocating to \(screen.localizedName, privacy: .public)")
        }

        let relocated = WindowGeometry.clamp(pinned.frame, into: screen.visibleFrame)
        guard displayLost || !WindowGeometry.isApproximatelyEqual(relocated, pinned.frame) else { return }

        guard let achieved = applyFrame(relocated, to: pinned.handle) else {
            markUnavailable()
            return
        }
        pinned.frame = achieved
        pinned.displayUUID = ScreenService.displayUUID(for: screen)
        state = .pinned(pinned)
        resetCorrectionBudget()
    }
}
