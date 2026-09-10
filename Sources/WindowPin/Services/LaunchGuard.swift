import AppKit

/// First-launch checks that explain what the app is doing.
///
/// A menu-bar-only app opens with no Dock icon and no window, which is
/// indistinguishable from "nothing happened" — especially on a multi-display
/// Mac where the menu bar icon may be on a screen the user is not looking at.
/// These two notices exist because silence looked like a crash.
@MainActor
enum LaunchGuard {
    /// macOS runs a quarantined app from a randomised read-only location until
    /// it is moved out of Downloads ("App Translocation").
    ///
    /// This matters far more here than for a normal app: the path changes on
    /// every launch, so the Accessibility and Screen Recording grants are
    /// attached to a location that will not exist next time. The app would
    /// appear to forget its permissions forever.
    static var isTranslocated: Bool {
        Bundle.main.bundlePath.contains("/AppTranslocation/")
    }

    private static let hasIntroducedKey = "com.windowpin.hasIntroduced"

    /// Runs once at startup. Returns `true` if the app should keep going.
    @discardableResult
    static func check() -> Bool {
        if isTranslocated {
            presentTranslocationAlert()
            return false
        }
        presentIntroductionIfFirstLaunch()
        return true
    }

    private static func presentTranslocationAlert() {
        Log.accessibility.notice("Running translocated from \(Bundle.main.bundlePath, privacy: .public)")

        let alert = NSAlert()
        alert.alertStyle = .critical
        alert.messageText = "Move Window Pin to your Applications folder"
        alert.informativeText = """
            macOS is running Window Pin from a temporary, read-only copy because \
            it is still in your Downloads folder.

            From there its location changes on every launch, so the Accessibility \
            permission can never stick and pinning will not work.

            Drag Window Pin into Applications, then open it again.
            """
        alert.addButton(withTitle: "Open Downloads")
        alert.addButton(withTitle: "Quit")

        NSApp.activate(ignoringOtherApps: true)
        if alert.runModal() == .alertFirstButtonReturn {
            // The translocated path is useless to the user; show the real
            // download instead so they can drag it where it belongs.
            NSWorkspace.shared.open(FileManager.default.urls(for: .downloadsDirectory,
                                                             in: .userDomainMask)[0])
        }
        NSApp.terminate(nil)
    }

    private static func presentIntroductionIfFirstLaunch() {
        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: hasIntroducedKey) else { return }
        defaults.set(true, forKey: hasIntroducedKey)

        let alert = NSAlert()
        alert.messageText = "Window Pin is running in your menu bar"
        alert.informativeText = """
            There is no Dock icon and no main window — look for the pin icon in \
            the menu bar and click it to get started.

            On a Mac with several displays, the menu bar icon appears on \
            whichever display currently has the menu bar.
            """
        alert.addButton(withTitle: "Got it")

        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }
}
