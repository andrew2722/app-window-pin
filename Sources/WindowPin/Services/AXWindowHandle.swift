import ApplicationServices
import CoreGraphics
import Foundation

/// The only type in the app that talks to `AXUIElement` for a *window*.
///
/// Everything above this layer (models, services, views) deals in `CGRect`s and
/// `Bool`s. Keeping the raw Accessibility calls here means the coordinate flip
/// and the error handling live in one testable place.
///
/// The instance is deliberately **not** `Sendable`: an `AXUIElement` must be
/// used from a single thread, and every method that touches it is `@MainActor`.
final class AXWindowHandle {
    /// Accessibility calls block until the owning app answers. A hung or busy
    /// app must not freeze our UI, so every request gets a short deadline.
    private static let messagingTimeout: Float = 0.35

    private let element: AXUIElement
    let pid: pid_t

    init(element: AXUIElement, pid: pid_t) {
        self.element = element
        self.pid = pid
        AXUIElementSetMessagingTimeout(element, Self.messagingTimeout)
    }

    /// Cheap, IPC-free identity. Two handles wrapping the same window produce
    /// the same token, which is what the picker uses for `Identifiable`.
    var identityToken: String {
        String(CFHash(element))
    }

    func isSameWindow(as other: AXWindowHandle) -> Bool {
        CFEqual(element, other.element)
    }

    // MARK: - Reading

    /// Frame in **AppKit** coordinates, or `nil` if the window has gone away.
    @MainActor
    func frame() -> CGRect? {
        guard let origin = point(for: kAXPositionAttribute),
              let size = size(for: kAXSizeAttribute) else { return nil }
        return WindowGeometry.appKitRect(fromAX: CGRect(origin: origin, size: size))
    }

    @MainActor
    func title() -> String? {
        copyAttribute(kAXTitleAttribute) as? String
    }

    @MainActor
    func subrole() -> String? {
        copyAttribute(kAXSubroleAttribute) as? String
    }

    @MainActor
    func role() -> String? {
        copyAttribute(kAXRoleAttribute) as? String
    }

    /// Whether this app is willing to let us move the window at all.
    ///
    /// This is the honest test for "pinnable": the Finder desktop, for example,
    /// looks like a window and reports a position, but refuses to have it set.
    @MainActor
    func isPositionSettable() -> Bool {
        var settable: DarwinBoolean = false
        guard AXUIElementIsAttributeSettable(element, kAXPositionAttribute as CFString, &settable) == .success else {
            return false
        }
        return settable.boolValue
    }

    @MainActor
    func isMinimized() -> Bool {
        copyAttribute(kAXMinimizedAttribute) as? Bool ?? false
    }

    /// `true` while the window still exists and its app still answers.
    @MainActor
    func isAlive() -> Bool {
        var value: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &value)
        return result == .success
    }

    // MARK: - Writing

    /// Moves and resizes the window to `appKitFrame`.
    ///
    /// Position is written twice on purpose. Many apps (Chrome and Terminal
    /// among them) clamp a move against their *current* size, so a window that
    /// is growing gets pushed back on-screen by the first write; re-applying
    /// the position after the resize lands it where the user asked.
    ///
    /// - Returns: `true` if every Accessibility write succeeded.
    @MainActor
    @discardableResult
    func setFrame(_ appKitFrame: CGRect) -> Bool {
        let axFrame = WindowGeometry.axRect(fromAppKit: appKitFrame)
        var ok = write(point: axFrame.origin, to: kAXPositionAttribute)
        ok = write(size: axFrame.size, to: kAXSizeAttribute) && ok
        ok = write(point: axFrame.origin, to: kAXPositionAttribute) && ok
        return ok
    }

    /// Makes this the app's main window without activating the app, so keys
    /// forwarded to that process land here.
    @discardableResult
    @MainActor
    func makeMain() -> Bool {
        AXUIElementSetAttributeValue(element, kAXMainAttribute as CFString, kCFBooleanTrue) == .success
    }

    /// Restores a minimised window.
    @discardableResult
    @MainActor
    func unminimize() -> Bool {
        AXUIElementSetAttributeValue(element, kAXMinimizedAttribute as CFString, kCFBooleanFalse) == .success
    }

    // MARK: - Observer plumbing

    /// Handed to `AXObserverAddNotification`, which needs the raw element.
    /// Only `WindowObserverService` calls this.
    @MainActor
    func withElement<T>(_ body: (AXUIElement) -> T) -> T {
        body(element)
    }

    // MARK: - Primitives

    @MainActor
    private func copyAttribute(_ attribute: String) -> CFTypeRef? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else {
            return nil
        }
        return value
    }

    @MainActor
    private func point(for attribute: String) -> CGPoint? {
        guard let value = axValue(for: attribute) else { return nil }
        var point = CGPoint.zero
        // Returns false if the attribute holds some other kind of AXValue.
        guard AXValueGetValue(value, .cgPoint, &point) else { return nil }
        return point
    }

    @MainActor
    private func size(for attribute: String) -> CGSize? {
        guard let value = axValue(for: attribute) else { return nil }
        var size = CGSize.zero
        guard AXValueGetValue(value, .cgSize, &size) else { return nil }
        return size
    }

    /// Checked bridge from an attribute to an `AXValue`.
    ///
    /// The `CFGetTypeID` test is what makes the downcast safe: `as?` on a
    /// CoreFoundation type always succeeds without checking anything, and
    /// handing a non-`AXValue` to `AXValueGetValue` would be undefined
    /// behaviour.
    @MainActor
    private func axValue(for attribute: String) -> AXValue? {
        guard let raw = copyAttribute(attribute), CFGetTypeID(raw) == AXValueGetTypeID() else {
            return nil
        }
        return unsafeDowncast(raw, to: AXValue.self)
    }

    @MainActor
    private func write(point: CGPoint, to attribute: String) -> Bool {
        var mutable = point
        guard let value = AXValueCreate(.cgPoint, &mutable) else { return false }
        return set(value, for: attribute)
    }

    @MainActor
    private func write(size: CGSize, to attribute: String) -> Bool {
        var mutable = size
        guard let value = AXValueCreate(.cgSize, &mutable) else { return false }
        return set(value, for: attribute)
    }

    @MainActor
    private func set(_ value: AXValue, for attribute: String) -> Bool {
        let result = AXUIElementSetAttributeValue(element, attribute as CFString, value)
        if result != .success {
            Log.pin.debug("Failed to set \(attribute, privacy: .public): AXError \(result.rawValue)")
        }
        return result == .success
    }
}
