import AppKit
import ApplicationServices
import Observation

/// Tracks whether the app is trusted for Accessibility.
///
/// macOS only re-evaluates trust for a running process when it is asked, so we
/// poll gently while permission is missing and stop entirely once it is granted.
/// The system prompt is shown at most once per launch — repeatedly calling
/// `AXIsProcessTrustedWithOptions` with the prompt flag is what produces the
/// "app keeps asking for permission" behaviour we want to avoid.
@MainActor
@Observable
final class AccessibilityService {
    private(set) var isTrusted: Bool = AXIsProcessTrusted()

    /// `true` once the user has been shown the system dialog this launch.
    private var hasPrompted = false
    private var pollTask: Task<Void, Never>?

    private static let settingsURL = URL(
        string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
    )

    init() {
        Log.accessibility.info("Accessibility trusted at launch: \(self.isTrusted, privacy: .public)")
        startPollingIfNeeded()
    }

    /// Re-reads trust immediately. Cheap; safe to call from the UI.
    @discardableResult
    func refresh() -> Bool {
        let trusted = AXIsProcessTrusted()
        if trusted != isTrusted {
            isTrusted = trusted
            Log.accessibility.info("Accessibility trust changed: \(trusted, privacy: .public)")
        }
        if trusted {
            pollTask?.cancel()
            pollTask = nil
        }
        return trusted
    }

    /// Shows the system permission dialog once, then relies on polling to
    /// notice the toggle being flipped.
    func requestPermission() {
        guard !isTrusted else { return }
        guard !hasPrompted else {
            openSettings()
            return
        }
        hasPrompted = true
        // The framework constant is an unsafe global `var`; its documented
        // value is stable and using it directly keeps this concurrency-clean.
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
        Log.accessibility.info("Requested Accessibility permission")
        startPollingIfNeeded()
    }

    func openSettings() {
        guard let url = Self.settingsURL else { return }
        NSWorkspace.shared.open(url)
    }

    /// Polls once a second, but only while permission is missing. Once granted
    /// the task ends and the app does no background work for this at all.
    private func startPollingIfNeeded() {
        guard !isTrusted, pollTask == nil else { return }
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                guard let self, !Task.isCancelled else { return }
                if self.refresh() { return }
            }
        }
    }
}
