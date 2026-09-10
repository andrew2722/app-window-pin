import ApplicationServices
import Foundation

/// Watches one window for movement, resizing and disappearance.
///
/// Prefers `AXObserver` notifications, which cost nothing while the window sits
/// still. Some apps never emit them, so registration failure downgrades to a
/// light poll instead of silently doing nothing.
///
/// `@MainActor` throughout: it owns an `AXUIElement` and a run loop source,
/// both of which must be touched from the thread they were created on.
@MainActor
final class WindowObserverService {
    enum Event {
        /// The window moved or was resized by someone else.
        case frameChanged
        /// The window (or its application) is gone.
        case vanished
    }

    /// How long to wait after the last move/resize notification before acting.
    /// Dragging a window emits a continuous stream of events; without this we
    /// would fight the user's mouse instead of snapping back when they stop.
    private static let settleDelay = Duration.milliseconds(160)
    /// Poll interval when `AXObserver` is unavailable for this app.
    private static let fallbackInterval = Duration.milliseconds(400)
    /// Interval for the liveness check when observers *are* working. One
    /// Accessibility call every two seconds is not measurable CPU.
    private static let livenessInterval = Duration.seconds(2)

    private var observer: AXObserver?
    private var handle: AXWindowHandle?
    private var onEvent: ((Event) -> Void)?
    private var settleTask: Task<Void, Never>?
    private var tickTask: Task<Void, Never>?
    private var lastKnownFrame: CGRect?

    /// `true` when this window had to fall back to polling. Surfaced in the UI
    /// so the behaviour is never a mystery.
    private(set) var isPolling = false

    func start(observing handle: AXWindowHandle, onEvent: @escaping (Event) -> Void) {
        stop()
        self.handle = handle
        self.onEvent = onEvent
        self.lastKnownFrame = handle.frame()

        if registerObserver(for: handle) {
            isPolling = false
            Log.observer.info("AXObserver registered for pid \(handle.pid, privacy: .public)")
        } else {
            isPolling = true
            Log.observer.notice("AXObserver unavailable for pid \(handle.pid, privacy: .public); polling instead")
        }
        startTicker()
    }

    func stop() {
        settleTask?.cancel()
        settleTask = nil
        tickTask?.cancel()
        tickTask = nil

        if let observer, let handle {
            handle.withElement { element in
                for notification in Self.notifications {
                    AXObserverRemoveNotification(observer, element, notification as CFString)
                }
            }
            CFRunLoopRemoveSource(CFRunLoopGetMain(),
                                  AXObserverGetRunLoopSource(observer),
                                  .defaultMode)
        }
        observer = nil
        handle = nil
        onEvent = nil
        lastKnownFrame = nil
        isPolling = false
    }

    /// Tells the observer what frame we just wrote, so the notification our own
    /// write produces is not mistaken for the user moving the window.
    func acknowledgeAppliedFrame(_ frame: CGRect) {
        lastKnownFrame = frame
    }

    // MARK: - AXObserver

    private static let notifications = [
        kAXWindowMovedNotification,
        kAXWindowResizedNotification,
        kAXUIElementDestroyedNotification
    ]

    private func registerObserver(for handle: AXWindowHandle) -> Bool {
        var created: AXObserver?
        guard AXObserverCreate(handle.pid, axObserverCallback, &created) == .success,
              let created else { return false }

        let context = Unmanaged.passUnretained(self).toOpaque()
        let registered = handle.withElement { element -> Bool in
            var anySucceeded = false
            for notification in Self.notifications {
                let result = AXObserverAddNotification(created, element, notification as CFString, context)
                if result == .success { anySucceeded = true }
            }
            return anySucceeded
        }

        guard registered else { return false }
        CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(created), .defaultMode)
        observer = created
        return true
    }

    /// Called from the C callback on the main run loop.
    fileprivate func handle(notification: String) {
        switch notification {
        case kAXUIElementDestroyedNotification:
            Log.observer.info("Window destroyed notification")
            emit(.vanished)
        case kAXWindowMovedNotification, kAXWindowResizedNotification:
            scheduleSettleCheck()
        default:
            break
        }
    }

    /// Coalesces a burst of move/resize notifications into one check.
    private func scheduleSettleCheck() {
        settleTask?.cancel()
        settleTask = Task { [weak self] in
            try? await Task.sleep(for: Self.settleDelay)
            guard !Task.isCancelled else { return }
            self?.checkFrame()
        }
    }

    // MARK: - Polling

    private func startTicker() {
        let interval = isPolling ? Self.fallbackInterval : Self.livenessInterval
        let checksFrame = isPolling
        tickTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: interval)
                guard !Task.isCancelled, let self else { return }
                if checksFrame {
                    self.checkFrame()
                } else {
                    self.checkLiveness()
                }
            }
        }
    }

    private func checkLiveness() {
        guard let handle else { return }
        if !handle.isAlive() { emit(.vanished) }
    }

    private func checkFrame() {
        guard let handle else { return }
        guard let frame = handle.frame() else {
            emit(.vanished)
            return
        }
        if let last = lastKnownFrame, WindowGeometry.isApproximatelyEqual(last, frame) { return }
        lastKnownFrame = frame
        emit(.frameChanged)
    }

    private func emit(_ event: Event) {
        onEvent?(event)
    }
}

/// `AXObserverCallback` must be a C function pointer, so it cannot be a method.
/// The observer is registered on the main run loop, which is what makes
/// `assumeIsolated` sound here.
private func axObserverCallback(_ observer: AXObserver,
                                _ element: AXUIElement,
                                _ notification: CFString,
                                _ context: UnsafeMutableRawPointer?) {
    guard let context else { return }
    let service = Unmanaged<WindowObserverService>.fromOpaque(context).takeUnretainedValue()
    let name = notification as String
    MainActor.assumeIsolated {
        service.handle(notification: name)
    }
}
