import AppKit
import CoreGraphics

/// Everything the app knows about displays.
///
/// All frames here are AppKit coordinates and always come from
/// `NSScreen.visibleFrame`, so the menu bar and the Dock are excluded without
/// any hardcoded insets.
@MainActor
enum ScreenService {
    static var screens: [NSScreen] { NSScreen.screens }

    static var primary: NSScreen? { WindowGeometry.primaryScreen }

    /// `CGDirectDisplayID` for a screen, used to remember which monitor a pin
    /// belongs to across screen-configuration changes.
    static func displayID(for screen: NSScreen) -> CGDirectDisplayID? {
        screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID
    }

    static func screen(withDisplayID displayID: CGDirectDisplayID) -> NSScreen? {
        screens.first { Self.displayID(for: $0) == displayID }
    }

    /// Stable identifier for a display, unlike `CGDirectDisplayID` which can be
    /// reassigned when monitors are unplugged. This is what gets persisted.
    static func displayUUID(for screen: NSScreen) -> String? {
        guard let displayID = displayID(for: screen),
              let uuid = CGDisplayCreateUUIDFromDisplayID(displayID)?.takeRetainedValue() else {
            return nil
        }
        return CFUUIDCreateString(nil, uuid) as String
    }

    static func screen(withDisplayUUID uuid: String) -> NSScreen? {
        screens.first { displayUUID(for: $0) == uuid }
    }

    /// The display that owns `frame` — the one holding the largest share of it.
    /// Falls back to the primary display for windows that are entirely
    /// off-screen (which happens after a monitor is unplugged).
    static func screen(containing frame: CGRect) -> NSScreen? {
        let best = screens.max { lhs, rhs in
            WindowGeometry.overlapArea(of: frame, with: lhs)
                < WindowGeometry.overlapArea(of: frame, with: rhs)
        }
        if let best, WindowGeometry.overlapArea(of: frame, with: best) > 0 {
            return best
        }
        return primary
    }

    static func humanName(for screen: NSScreen) -> String {
        screen.localizedName
    }

    /// Computes the frame for a snap preset on `screen`.
    ///
    /// - Parameter currentSize: used by `.custom`, which keeps the window's own
    ///   size and only repositions it.
    static func frame(position: PositionPreset,
                      size: SizePreset,
                      on screen: NSScreen,
                      currentSize: CGSize) -> CGRect {
        let bounds = screen.visibleFrame
        let resolved = self.size(for: size, on: screen, currentSize: currentSize)
        let origin = resolveOrigin(position, size: resolved, in: bounds)
        return WindowGeometry.clamp(CGRect(origin: origin, size: resolved), into: bounds)
    }

    /// The size a preset resolves to on `screen`, without choosing a position.
    /// Used when the user picks a size before picking a corner.
    static func size(for preset: SizePreset, on screen: NSScreen, currentSize: CGSize) -> CGSize {
        resolveSize(preset, in: screen.visibleFrame, currentSize: currentSize)
    }

    private static func resolveSize(_ preset: SizePreset,
                                    in bounds: CGRect,
                                    currentSize: CGSize) -> CGSize {
        switch preset {
        case .widthFraction(let fraction):
            return CGSize(width: (bounds.width * fraction).rounded(), height: bounds.height)
        case .portrait:
            return CGSize(width: min(SizePreset.portraitSize.width, bounds.width),
                          height: min(SizePreset.portraitSize.height, bounds.height))
        case .custom:
            return CGSize(width: min(currentSize.width, bounds.width),
                          height: min(currentSize.height, bounds.height))
        }
    }

    private static func resolveOrigin(_ preset: PositionPreset,
                                      size: CGSize,
                                      in bounds: CGRect) -> CGPoint {
        // AppKit coordinates: y grows upward, so "top" is `maxY`.
        switch preset {
        case .topLeft:
            return CGPoint(x: bounds.minX, y: bounds.maxY - size.height)
        case .topRight:
            return CGPoint(x: bounds.maxX - size.width, y: bounds.maxY - size.height)
        case .bottomLeft:
            return CGPoint(x: bounds.minX, y: bounds.minY)
        case .bottomRight:
            return CGPoint(x: bounds.maxX - size.width, y: bounds.minY)
        case .center:
            return CGPoint(x: bounds.midX - size.width / 2, y: bounds.midY - size.height / 2)
        }
    }
}
