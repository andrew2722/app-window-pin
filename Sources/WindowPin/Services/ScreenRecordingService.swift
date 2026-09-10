import AppKit
import CoreGraphics
import Observation

/// Tracks Screen Recording permission, which ScreenCaptureKit needs before it
/// will hand over a single frame of another application's window.
///
/// Mirrors the shape of `AccessibilityService`: prompt at most once per launch,
/// poll gently only while permission is missing, stop the moment it arrives.
@MainActor
@Observable
final class ScreenRecordingService {
    private(set) var isAuthorized: Bool = CGPreflightScreenCaptureAccess()

    private var hasPrompted = false
    @ObservationIgnored private var pollTask: Task<Void, Never>?

    private static let settingsURL = URL(
        string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture"
    )

    init() {
        Log.mirror.info("Screen Recording authorised at launch: \(self.isAuthorized, privacy: .public)")
        startPollingIfNeeded()
    }

    @discardableResult
    func refresh() -> Bool {
        let authorized = CGPreflightScreenCaptureAccess()
        if authorized != isAuthorized {
            isAuthorized = authorized
            Log.mirror.info("Screen Recording permission changed: \(authorized, privacy: .public)")
        }
        if authorized {
            pollTask?.cancel()
            pollTask = nil
        }
        return authorized
    }

    /// Shows the system prompt once. macOS requires the app to be relaunched
    /// after the switch is flipped, which `needsRelaunchNotice` surfaces.
    func request() {
        guard !isAuthorized else { return }
        guard !hasPrompted else {
            openSettings()
            return
        }
        hasPrompted = true
        CGRequestScreenCaptureAccess()
        Log.mirror.info("Requested Screen Recording permission")
        startPollingIfNeeded()
    }

    /// Screen Recording, unlike Accessibility, is only re-read by the system
    /// when the process restarts. Once we have asked, the UI has to tell the
    /// user that much rather than silently doing nothing.
    var needsRelaunchNotice: Bool { hasPrompted && !isAuthorized }

    func openSettings() {
        guard let url = Self.settingsURL else { return }
        NSWorkspace.shared.open(url)
    }

    private func startPollingIfNeeded() {
        guard !isAuthorized, pollTask == nil else { return }
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                guard let self, !Task.isCancelled else { return }
                if self.refresh() { return }
            }
        }
    }
}
