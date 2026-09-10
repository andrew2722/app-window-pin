import AppKit

/// The thumbtack the app is named after, defined once.
///
/// Two places draw it at wildly different sizes — the menu bar at 15pt and
/// `Scripts/make-assets.swift` at 1024px for the app icon — and they compile
/// against this same file so the icon and the status item can never drift into
/// being two different-looking pins.
///
/// Note the app icon deliberately does *not* use SF Symbols: Apple's SF Symbols
/// license forbids their use in app icons, so the pin is drawn by hand.
enum PinGlyph {

    /// Nominal artwork bounds, with the point at the origin and the body
    /// extending up +y. Callers scale from these numbers.
    static let nominalSize = CGSize(width: 140, height: 162)

    /// A thumbtack: flat cap, narrow stem, tapered spike.
    ///
    /// Built as one closed contour rather than a cap rect plus a stem rect plus
    /// a spike. Overlapping subpaths fill the same but *stroke* wrong — the
    /// outline style would draw the seams where the parts meet, turning the pin
    /// into something that reads like a screw.
    static func path(scale s: CGFloat) -> CGPath {
        // Corners of the silhouette, from the point and up the right-hand side,
        // each with the radius its fillet should get.
        let corners: [(point: CGPoint, radius: CGFloat)] = [
            (CGPoint(x: 0, y: 0), 4),        // spike point
            (CGPoint(x: 26, y: 66), 7),      // spike meets stem
            (CGPoint(x: 26, y: 110), 8),     // stem meets cap
            (CGPoint(x: 70, y: 110), 12),    // cap underside
            (CGPoint(x: 70, y: 162), 20),    // cap top
            (CGPoint(x: -70, y: 162), 20),
            (CGPoint(x: -70, y: 110), 12),
            (CGPoint(x: -26, y: 110), 8),
            (CGPoint(x: -26, y: 66), 7),
        ]

        let scaled = corners.map {
            (point: CGPoint(x: $0.point.x * s, y: $0.point.y * s), radius: $0.radius * s)
        }
        let path = CGMutablePath()
        // Start mid-edge so the first fillet has a run-up to curve out of.
        let first = scaled[0].point, second = scaled[1].point
        path.move(to: CGPoint(x: (first.x + second.x) / 2, y: (first.y + second.y) / 2))
        for i in 1...scaled.count {
            let corner = scaled[i % scaled.count]
            let next = scaled[(i + 1) % scaled.count]
            path.addArc(tangent1End: corner.point, tangent2End: next.point, radius: corner.radius)
        }
        path.closeSubpath()
        return path
    }

    /// How the status item should read at a glance.
    enum Style {
        /// Nothing pinned — hollow.
        case outline
        /// Holding a window — solid.
        case filled
        /// Can't pin right now — solid with a slash.
        case unavailable
    }

    /// A status-item image.
    ///
    /// Marked as a template so macOS inverts it for dark menu bars and for the
    /// highlighted state while the menu is open; drawing it in a fixed colour
    /// would leave a black pin on a black background whenever the menu opens.
    @MainActor
    static func menuBarImage(_ style: Style) -> NSImage {
        if let cached = cache[style] { return cached }

        let height: CGFloat = 15
        let s = height / nominalSize.height
        let width = nominalSize.width * s
        // A point of slack all round keeps the slash and the stroked outline
        // from being clipped by the image edge.
        let size = NSSize(width: (width + 3).rounded(.up), height: height + 2)

        let image = NSImage(size: size, flipped: false) { _ in
            guard let ctx = NSGraphicsContext.current?.cgContext else { return false }
            let black = CGColor(gray: 0, alpha: 1)
            ctx.translateBy(x: size.width / 2, y: 1)
            ctx.setLineJoin(.round)

            switch style {
            case .outline:
                ctx.addPath(path(scale: s))
                ctx.setStrokeColor(black)
                ctx.setLineWidth(max(1.2, 13 * s))
                ctx.strokePath()

            case .filled:
                ctx.addPath(path(scale: s))
                ctx.setFillColor(black)
                ctx.fillPath()

            case .unavailable:
                ctx.addPath(path(scale: s))
                ctx.setFillColor(black)
                ctx.fillPath()

                let from = CGPoint(x: -width / 2 - 1, y: -0.5)
                let to = CGPoint(x: width / 2 + 1, y: height + 0.5)
                // Clear a wider channel first so the slash stays visible where
                // it crosses the solid cap.
                ctx.setBlendMode(.clear)
                ctx.setLineWidth(max(2.2, 24 * s))
                ctx.strokeLineSegments(between: [from, to])
                ctx.setBlendMode(.normal)
                ctx.setStrokeColor(black)
                ctx.setLineWidth(max(1.3, 14 * s))
                ctx.strokeLineSegments(between: [from, to])
            }
            return true
        }

        image.isTemplate = true
        cache[style] = image
        return image
    }

    @MainActor private static var cache: [Style: NSImage] = [:]
}
