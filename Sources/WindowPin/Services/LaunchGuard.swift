import AppKit

/// First-launch checks that explain what the app is doing — and fix it.
///
/// A menu-bar-only app opens with no Dock icon and no window, which is
/// indistinguishable from "nothing happened", especially on a multi-display Mac
/// where the icon may be on a screen the user is not looking at.
@MainActor
enum LaunchGuard {
    /// macOS runs a quarantined app from a randomised read-only copy until it
    /// is moved out of Downloads ("App Translocation").
    ///
    /// This matters more here than for a normal app: the path changes on every
    /// launch, so Accessibility and Screen Recording grants attach to a
    /// location that will not exist next time. The app would appear to forget
    /// its permissions forever.
    static var isTranslocated: Bool {
        Bundle.main.bundlePath.contains("/AppTranslocation/")
    }

    private static let hasIntroducedKey = "com.windowpin.hasIntroduced"

    /// Runs once at startup. Returns `true` if the app should keep going.
    @discardableResult
    static func check() -> Bool {
        if isTranslocated {
            handleTranslocation()
            return false
        }
        if let running = otherRunningInstance() {
            handleAlreadyRunning(running)
            return false
        }
        presentIntroductionIfFirstLaunch()
        return true
    }

    // MARK: - One instance

    /// Another copy of this app that is already running properly.
    ///
    /// Nothing stopped a second copy before, and because the app is invisible
    /// apart from a menu bar icon that is easy to miss, people open it again —
    /// five launches in twenty-six seconds in one log. Two instances mean two
    /// menu bar icons and two pin services pulling the same window towards two
    /// different remembered frames.
    ///
    /// Translocated copies are ignored: one may be mid-handover, having just
    /// installed this very instance and be about to quit.
    private static func otherRunningInstance() -> NSRunningApplication? {
        guard let bundleID = Bundle.main.bundleIdentifier else { return nil }
        let ownPID = ProcessInfo.processInfo.processIdentifier
        return NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first {
            $0.processIdentifier != ownPID
                && !($0.bundleURL?.path.contains("/AppTranslocation/") ?? false)
        }
    }

    /// Hands over to the copy that is already running and quits.
    ///
    /// No dialog: LaunchServices already refuses to start a second process for
    /// the same bundle identifier, so this only fires for copies it treats as
    /// distinct — a renamed duplicate, or a translocated one. Silently handing
    /// over is what macOS does when you open an app that is already open, and a
    /// modal presented this early in launch does not display anyway.
    private static func handleAlreadyRunning(_ instance: NSRunningApplication) {
        Log.accessibility.notice("Another instance is already running; handing over to it")
        instance.activate()
        NSApp.terminate(nil)
    }

    // MARK: - Translocation

    /// Offers to install the app properly, because telling someone to go and
    /// drag a file is asking them to do work the app can simply do. Refusing to
    /// run without offering the fix just produces the same dialog every time
    /// they double-click.
    private static func handleTranslocation() {
        Log.accessibility.notice("Running translocated from \(Bundle.main.bundlePath, privacy: .public)")

        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Window Pin needs to live in Applications"
        alert.informativeText = """
            macOS is running it from a temporary, read-only copy because it was \
            opened straight from Downloads. From there its location changes every \
            launch, so permissions can never be saved.

            Window Pin can move itself and reopen from the right place.
            """
        alert.addButton(withTitle: "Move to Applications")
        alert.addButton(withTitle: "Quit")

        NSApp.activate(ignoringOtherApps: true)
        guard alert.runModal() == .alertFirstButtonReturn else {
            NSApp.terminate(nil)
            return
        }

        do {
            let installed = try installIntoApplications()
            relaunch(at: installed)
        } catch {
            let failure = NSAlert()
            failure.alertStyle = .critical
            failure.messageText = "Could not move Window Pin"
            failure.informativeText = """
                \(error.localizedDescription)

                Drag Window Pin from your Downloads folder into Applications \
                yourself, then open it from there.
                """
            failure.addButton(withTitle: "Open Downloads")
            failure.addButton(withTitle: "Quit")
            if failure.runModal() == .alertFirstButtonReturn,
               let downloads = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first {
                NSWorkspace.shared.open(downloads)
            }
            NSApp.terminate(nil)
        }
    }

    /// Copies the app into Applications and returns where it landed.
    ///
    /// The translocated bundle is copied directly. It is a complete, correctly
    /// signed copy of the app — that is what translocation makes — so there is
    /// no need to locate the original in Downloads. (`SecTranslocate…` would
    /// give that path but is not exposed to Swift.)
    private static func installIntoApplications() throws -> URL {
        let source = Bundle.main.bundleURL
        let fileManager = FileManager.default

        // Fall back to the user's own Applications folder when /Applications
        // needs an administrator, so this still works without a password.
        var directory = URL(fileURLWithPath: "/Applications", isDirectory: true)
        if !fileManager.isWritableFile(atPath: directory.path) {
            directory = try fileManager.url(for: .applicationDirectory,
                                            in: .userDomainMask,
                                            appropriateFor: nil,
                                            create: true)
        }

        let destination = directory.appendingPathComponent(source.lastPathComponent)

        // Replacing a bundle while it is executing pulls the code out from
        // under the running process. If a copy is already installed and live,
        // that copy is the one the user wants — hand over to it instead.
        if let installed = runningInstance(at: destination) {
            installed.activate()
            NSApp.terminate(nil)
            return destination
        }

        if fileManager.fileExists(atPath: destination.path) {
            try fileManager.removeItem(at: destination)
        }
        try fileManager.copyItem(at: source, to: destination)

        // A programmatic copy keeps the quarantine flag, and a quarantined app
        // gets translocated again — which would land us right back here. Finder
        // clears this when *it* moves an app; we have to do it ourselves.
        clearQuarantine(at: destination)
        return destination
    }

    /// A running instance whose bundle is exactly `url`.
    private static func runningInstance(at url: URL) -> NSRunningApplication? {
        guard let bundleID = Bundle.main.bundleIdentifier else { return nil }
        let ownPID = ProcessInfo.processInfo.processIdentifier
        return NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first {
            $0.processIdentifier != ownPID
                && $0.bundleURL?.standardizedFileURL == url.standardizedFileURL
        }
    }

    private static func clearQuarantine(at url: URL) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/xattr")
        process.arguments = ["-dr", "com.apple.quarantine", url.path]
        try? process.run()
        process.waitUntilExit()
    }

    private static func relaunch(at url: URL) {
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        NSWorkspace.shared.openApplication(at: url, configuration: configuration) { _, _ in
            Task { @MainActor in NSApp.terminate(nil) }
        }
    }

    // MARK: - First launch

    private static func presentIntroductionIfFirstLaunch() {
        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: hasIntroducedKey) else { return }

        let alert = NSAlert()
        alert.messageText = "Window Pin is running in your menu bar"
        alert.informativeText = """
            There is no Dock icon and no main window — look for the pin icon in \
            the menu bar and click it to get started.

            On a Mac with several displays, the icon appears on whichever \
            display currently has the menu bar.
            """
        alert.addButton(withTitle: "Got it")

        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()

        // Marked as shown only once it has been. Setting the flag first would
        // burn the one introduction the user gets if the alert ever failed to
        // display — which is exactly what happened on the already-running path.
        defaults.set(true, forKey: hasIntroducedKey)
    }
}
