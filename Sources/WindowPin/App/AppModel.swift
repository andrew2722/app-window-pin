import AppKit
import Observation

/// Ties the services together and holds the state the UI edits.
///
/// Views talk only to this type — no view ever touches an `AXUIElement`.
@MainActor
@Observable
final class AppModel {
    let accessibility = AccessibilityService()
    let discovery = WindowDiscoveryService()
    let pinService = WindowPinService()

    /// Identifier of the window highlighted in the picker.
    var selectedWindowID: String?
    /// Last snap position the user chose, `nil` until they pick one.
    var position: PositionPreset?
    var size: SizePreset = .custom
    /// Width/height used when `size == .custom`; prefilled from the selection.
    var customSize = CGSize(width: 420, height: 700)

    /// A pin loaded from disk that has not been re-applied yet. Present only
    /// when the previously pinned window has been found again.
    private(set) var restorablePin: PinConfiguration?

    @ObservationIgnored private var savedConfiguration: PinConfiguration?

    init() {
        savedConfiguration = PinStore.load()
        if let saved = savedConfiguration {
            position = saved.position
            size = saved.size
            customSize = saved.frame.size
        }
    }

    // MARK: - Selection

    var selectedWindow: WindowInfo? {
        discovery.windows.first { $0.id == selectedWindowID }
    }

    /// The window the controls act on: the pinned one if there is one,
    /// otherwise whatever is selected in the picker.
    var activeAppName: String? {
        pinService.state.pinnedWindow?.appName ?? selectedWindow?.appName
    }

    var activeTitle: String? {
        pinService.state.pinnedWindow?.title ?? selectedWindow?.title
    }

    var activeFrame: CGRect? {
        pinService.state.pinnedWindow?.frame ?? selectedWindow?.frame
    }

    /// Owning process of the active window, so the UI can show its app icon.
    var activePID: pid_t? {
        pinService.state.pinnedWindow?.pid ?? selectedWindow?.pid
    }

    var canPin: Bool {
        accessibility.isTrusted && selectedWindow != nil && !pinService.state.isPinned
    }

    func select(_ window: WindowInfo) {
        selectedWindowID = window.id
        if size == .custom {
            customSize = window.frame.size
        }
    }

    // MARK: - Discovery

    func refresh() {
        accessibility.refresh()
        discovery.refresh()

        // Selection is keyed by window number, which survives most refreshes.
        // If the window did go away, drop the stale selection.
        if selectedWindow == nil { selectedWindowID = nil }
        resolveSavedPinIfPossible()
    }

    /// Looks for the previously pinned window, but never moves it — the user
    /// has to ask for the pin to be re-applied.
    private func resolveSavedPinIfPossible() {
        guard let saved = savedConfiguration, saved.wasPinned, !pinService.state.isPinned else {
            restorablePin = nil
            return
        }
        guard let match = discovery.findWindow(bundleIdentifier: saved.bundleIdentifier,
                                               title: saved.title) else {
            restorablePin = nil
            return
        }
        restorablePin = saved
        if selectedWindowID == nil { selectedWindowID = match.id }
    }

    /// Re-applies the saved pin to the window we just matched.
    func restoreSavedPin() {
        guard let saved = restorablePin, let window = selectedWindow else { return }
        let screen = saved.displayUUID.flatMap(ScreenService.screen(withDisplayUUID:))
            ?? ScreenService.screen(containing: saved.frame)
        let frame = screen.map { WindowGeometry.clamp(saved.frame, into: $0.visibleFrame) } ?? saved.frame
        pinService.pin(window, at: frame)
        restorablePin = nil
        persist()
    }

    func discardSavedPin() {
        restorablePin = nil
        savedConfiguration = nil
        PinStore.clear()
    }

    // MARK: - Actions

    func pin() {
        guard let window = selectedWindow else { return }
        pinService.pin(window, at: window.frame)
        persist()
    }

    func unpin() {
        pinService.unpin()
        persist()
        discovery.refresh()
    }

    func dismissUnavailable() {
        pinService.dismissUnavailable()
    }

    /// Applies the current position/size presets to the active window.
    /// Works whether or not the window is pinned; when it is, the pinned frame
    /// is updated so the new layout is what gets held.
    func applySnap(position newPosition: PositionPreset? = nil, size newSize: SizePreset? = nil) {
        if let newPosition { position = newPosition }
        if let newSize { size = newSize }

        guard let handle = activeHandle, let currentFrame = activeFrame else { return }
        guard let screen = ScreenService.screen(containing: currentFrame) else { return }

        // `.custom` means the size the user typed; every other preset is
        // derived from the display, so the window's own size is what matters.
        let referenceSize = size == .custom ? customSize : currentFrame.size

        // Choosing a size before choosing a corner resizes the window where it
        // already is, rather than doing nothing.
        let frame: CGRect
        if let position {
            frame = ScreenService.frame(position: position,
                                        size: size,
                                        on: screen,
                                        currentSize: referenceSize)
        } else {
            let resized = CGRect(origin: currentFrame.origin,
                                 size: ScreenService.size(for: size, on: screen, currentSize: referenceSize))
            frame = WindowGeometry.clamp(resized, into: screen.visibleFrame)
        }

        if pinService.state.isPinned {
            pinService.updatePinnedFrame(frame)
        } else {
            pinService.applyFrame(frame, to: handle)
            discovery.refresh()
        }
        persist()
    }

    private var activeHandle: AXWindowHandle? {
        pinService.state.pinnedWindow?.handle ?? selectedWindow?.handle
    }

    // MARK: - Persistence

    /// Saves the current pin and preset choices so they survive a relaunch.
    func persist() {
        guard let appName = activeAppName, let frame = activeFrame else { return }
        let pinned = pinService.state.pinnedWindow
        let configuration = PinConfiguration(
            bundleIdentifier: pinned?.bundleIdentifier ?? selectedWindow?.bundleIdentifier,
            appName: appName,
            title: activeTitle ?? "",
            frame: frame,
            displayUUID: pinned?.displayUUID
                ?? ScreenService.screen(containing: frame).flatMap(ScreenService.displayUUID(for:)),
            position: position,
            size: size,
            wasPinned: pinned != nil
        )
        savedConfiguration = configuration
        PinStore.save(configuration)
    }
}
