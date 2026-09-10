import AppKit
import CoreGraphics

/// The one place that knows how the two macOS coordinate systems relate.
///
/// - **AppKit** (`NSScreen.frame`, `NSScreen.visibleFrame`): origin is the
///   bottom-left of the primary display, `y` grows upward.
/// - **Accessibility / CoreGraphics** (`kAXPositionAttribute`): origin is the
///   top-left of the primary display, `y` grows downward.
///
/// Every frame that leaves this app for the Accessibility API goes through
/// `axRect(fromAppKit:)`, and every frame that arrives from it goes through
/// `appKitRect(fromAX:)`. Nothing else in the codebase performs a flip.
enum WindowGeometry {
    /// The display that owns the global origin. AppKit guarantees exactly one
    /// screen has `frame.origin == .zero`; that display's height defines the
    /// flip axis for every other display, including ones above or left of it
    /// (which legitimately have negative coordinates in both systems).
    static var primaryScreen: NSScreen? {
        NSScreen.screens.first { $0.frame.origin == .zero } ?? NSScreen.screens.first
    }

    /// `maxY` of the primary display in AppKit coordinates — the axis both
    /// coordinate systems are mirrored across.
    static var flipAxis: CGFloat {
        primaryScreen?.frame.maxY ?? 0
    }

    /// AppKit rect -> Accessibility rect. The conversion is its own inverse,
    /// which is why both directions share an implementation.
    static func axRect(fromAppKit rect: CGRect) -> CGRect {
        flipped(rect)
    }

    /// Accessibility rect -> AppKit rect.
    static func appKitRect(fromAX rect: CGRect) -> CGRect {
        flipped(rect)
    }

    private static func flipped(_ rect: CGRect) -> CGRect {
        CGRect(x: rect.origin.x,
               y: flipAxis - rect.maxY,
               width: rect.width,
               height: rect.height)
    }

    /// Two frames are "the same" when every edge is within half a point.
    /// Some apps (Chrome, Terminal) quantise size to their own grid, so an
    /// exact comparison would make us re-apply a frame forever.
    static func isApproximatelyEqual(_ a: CGRect, _ b: CGRect, tolerance: CGFloat = 0.5) -> Bool {
        abs(a.origin.x - b.origin.x) <= tolerance
            && abs(a.origin.y - b.origin.y) <= tolerance
            && abs(a.width - b.width) <= tolerance
            && abs(a.height - b.height) <= tolerance
    }

    /// Keeps `rect` inside `bounds`, shrinking it first if it simply does not fit.
    /// Used when a pinned window has to be relocated onto a smaller display.
    static func clamp(_ rect: CGRect, into bounds: CGRect) -> CGRect {
        let width = min(rect.width, bounds.width)
        let height = min(rect.height, bounds.height)
        let x = min(max(rect.origin.x, bounds.minX), bounds.maxX - width)
        let y = min(max(rect.origin.y, bounds.minY), bounds.maxY - height)
        return CGRect(x: x, y: y, width: width, height: height)
    }

    /// Area of `rect` that lands on `screen`, in AppKit coordinates. Used to
    /// decide which display "owns" a window when it straddles two of them.
    static func overlapArea(of rect: CGRect, with screen: NSScreen) -> CGFloat {
        let intersection = rect.intersection(screen.frame)
        guard !intersection.isNull else { return 0 }
        return intersection.width * intersection.height
    }
}

extension CGSize {
    /// How a window size is written everywhere in the interface.
    ///
    /// Built as a plain `String` on purpose: handing the numbers to `Text`'s
    /// localized interpolation instead would group them ("1,440"), and the two
    /// places that show a size would disagree on the format.
    var displayDescription: String {
        "\(Int(width.rounded())) × \(Int(height.rounded()))"
    }
}
