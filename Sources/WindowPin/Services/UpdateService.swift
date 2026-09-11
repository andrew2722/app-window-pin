import AppKit
import Observation
import Sparkle

/// Keeps an installed copy up to date without the user going back to the
/// download page.
///
/// Everything about the feed lives in `Info.plist` (`SUFeedURL`,
/// `SUPublicEDKey`, and the automatic-check switches) so that
/// `Scripts/build-app.sh` is the single place that decides where updates come
/// from, and so a build with no feed configured simply has no updater rather
/// than a broken one.
///
/// Updates normally install themselves in the background. The alternative —
/// telling someone a new version exists and leaving them to download and
/// replace the app by hand — is the situation this was written to end.
@MainActor
@Observable
final class UpdateService {
    /// False while a check is already running, and in a build with no feed.
    private(set) var canCheck = false

    /// Set when Sparkle found an update it wants to show and we asked to
    /// present it ourselves — see `UpdateUserDriverDelegate`.
    private(set) var pendingVersion: String?

    /// `nil` outside an app bundle, or when this build ships without a feed.
    @ObservationIgnored private let controller: SPUStandardUpdaterController?
    @ObservationIgnored private let userDriver = UpdateUserDriverDelegate()
    @ObservationIgnored private var canCheckObservation: NSKeyValueObservation?

    init() {
        guard let feed = Self.configuredFeedURL else {
            controller = nil
            Log.update.notice("No SUFeedURL in the bundle; automatic updates are off in this build")
            return
        }

        let controller = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: nil,
            userDriverDelegate: userDriver
        )
        self.controller = controller
        userDriver.owner = self
        Log.update.info("Update feed: \(feed, privacy: .public)")

        // `canCheckForUpdates` is false while a check is in flight, which is
        // what stops the manual control from queueing a second one.
        canCheckObservation = controller.updater.observe(
            \.canCheckForUpdates,
            options: [.initial, .new]
        ) { [weak self] updater, _ in
            // Read on whichever thread KVO fired, carry the value across.
            let value = updater.canCheckForUpdates
            Task { @MainActor [weak self] in self?.canCheck = value }
        }
    }

    /// Checks now, showing Sparkle's own progress and release notes.
    ///
    /// Also the way an update we are holding gets shown: when a scheduled check
    /// finds one, Sparkle waits for exactly this call to display it.
    func checkNow() {
        guard let controller else { return }
        NSApp.activate(ignoringOtherApps: true)
        controller.checkForUpdates(nil)
    }

    /// The feed this build points at, or `nil` if it has none.
    ///
    /// A missing key is the normal case for a bare `swift build` executable and
    /// for the preview harness, neither of which is an app bundle.
    static var configuredFeedURL: String? {
        guard let feed = Bundle.main.infoDictionary?["SUFeedURL"] as? String,
              !feed.isEmpty else { return nil }
        return feed
    }

    fileprivate func noteUpdateWaiting(version: String?) {
        pendingVersion = version
        Log.update.notice("Holding \(version ?? "an update", privacy: .public) until the user asks for it")
    }

    fileprivate func clearPendingUpdate() {
        pendingVersion = nil
    }
}

/// Decides how an update announces itself in an app that has no windows.
///
/// Sparkle's default is to open its update window as soon as a scheduled check
/// finds something. For an app with no Dock icon that window arrives behind
/// whatever the user is working in, and Sparkle then waits for an answer to a
/// question nobody saw — Sparkle logs a warning about exactly this. So a
/// background find is held instead, and shown in the two places the user
/// already looks at this app: a dot on the menu bar icon and the version in the
/// controller. A find the user is looking at is left to Sparkle to present.
private final class UpdateUserDriverDelegate: NSObject, SPUStandardUserDriverDelegate {
    /// Set immediately after the updater is constructed; `weak` because the
    /// service owns this delegate.
    weak var owner: UpdateService?

    var supportsGentleScheduledUpdateReminders: Bool { true }

    func standardUserDriverShouldHandleShowingScheduledUpdate(_ update: SUAppcastItem,
                                                             andInImmediateFocus immediateFocus: Bool) -> Bool {
        // `immediateFocus` means the user is already in front of an update
        // window, so letting Sparkle continue is not an interruption.
        immediateFocus
    }

    func standardUserDriverWillHandleShowingUpdate(_ handleShowingUpdate: Bool,
                                                   forUpdate update: SUAppcastItem,
                                                   state: SPUUserUpdateState) {
        let version = update.displayVersionString
        let userInitiated = state.userInitiated
        Task { @MainActor [weak owner] in
            guard handleShowingUpdate else {
                owner?.noteUpdateWaiting(version: version)
                return
            }
            // Sparkle is about to put a window on screen. Bring the app forward
            // so it lands in front rather than behind the user's work.
            if !userInitiated {
                NSApp.activate(ignoringOtherApps: true)
            }
        }
    }

    func standardUserDriverDidReceiveUserAttention(forUpdate update: SUAppcastItem) {
        Task { @MainActor [weak owner] in owner?.clearPendingUpdate() }
    }

    func standardUserDriverWillFinishUpdateSession() {
        Task { @MainActor [weak owner] in owner?.clearPendingUpdate() }
    }
}
