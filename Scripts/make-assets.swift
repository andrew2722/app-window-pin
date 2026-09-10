import AppKit
import CoreGraphics

// Draws every image the project ships: the app icon iconset and the two README
// figures. Everything is vector CoreGraphics, so the art is reproducible from
// source and re-renders cleanly at any size — run `make assets` after editing.
//
// Compiled together with Sources/WindowPin/Utilities/PinGlyph.swift by
// Scripts/make-assets.sh, which also folds the iconset into an .icns.

// MARK: - Palette

private func rgb(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> CGColor {
    CGColor(red: r / 255, green: g / 255, blue: b / 255, alpha: a)
}

private enum Palette {
    static let plateTop = rgb(92, 141, 255)
    static let plateBottom = rgb(46, 66, 196)
    static let pin = rgb(255, 178, 50)
    static let windowFace = rgb(252, 253, 255)
    static let windowChrome = rgb(224, 231, 243)
    static let windowText = rgb(196, 206, 224)
    static let ink = rgb(18, 22, 34)
    static let heroTop = rgb(30, 38, 66)
    static let heroBottom = rgb(14, 17, 30)
    static let desktop = rgb(236, 238, 246)
}

// MARK: - Drawing helpers

/// A superellipse — the continuous-corner "squircle" macOS icon plates use.
/// A plain rounded rect reads visibly rounder than the system icons beside it.
private func squircle(in rect: CGRect, n: CGFloat = 6.2) -> CGPath {
    let path = CGMutablePath()
    let a = rect.width / 2, b = rect.height / 2
    let cx = rect.midX, cy = rect.midY
    let steps = 720
    for i in 0...steps {
        let t = CGFloat(i) / CGFloat(steps) * 2 * .pi
        let ct = cos(t), st = sin(t)
        let x = cx + a * pow(abs(ct), 2 / n) * (ct < 0 ? -1 : 1)
        let y = cy + b * pow(abs(st), 2 / n) * (st < 0 ? -1 : 1)
        i == 0 ? path.move(to: CGPoint(x: x, y: y)) : path.addLine(to: CGPoint(x: x, y: y))
    }
    path.closeSubpath()
    return path
}

private func rounded(_ r: CGRect, _ radius: CGFloat) -> CGPath {
    CGPath(roundedRect: r, cornerWidth: radius, cornerHeight: radius, transform: nil)
}

private func linearGradient(_ ctx: CGContext, in rect: CGRect, _ from: CGColor, _ to: CGColor,
                            diagonal: Bool = true) {
    let grad = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                          colors: [from, to] as CFArray, locations: [0, 1])!
    let start = CGPoint(x: rect.minX, y: rect.maxY)
    let end = diagonal ? CGPoint(x: rect.maxX, y: rect.minY) : CGPoint(x: rect.minX, y: rect.minY)
    ctx.drawLinearGradient(grad, start: start, end: end, options: [])
}

private func fill(_ ctx: CGContext, _ path: CGPath, _ color: CGColor) {
    ctx.addPath(path)
    ctx.setFillColor(color)
    ctx.fillPath()
}

private func shadowed(_ ctx: CGContext, offset: CGSize, blur: CGFloat, alpha: CGFloat,
                      _ body: (CGContext) -> Void) {
    ctx.saveGState()
    ctx.setShadow(offset: offset, blur: blur, color: CGColor(gray: 0, alpha: alpha))
    body(ctx)
    ctx.restoreGState()
}

/// Renders `body` into a PNG at `path`. The context is unflipped (y grows up),
/// matching CoreGraphics and the coordinates every draw function here uses.
private func renderPNG(width: Int, height: Int, to path: String, _ body: (CGContext) -> Void) throws {
    guard let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height,
                                        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                        isPlanar: false, colorSpaceName: .deviceRGB,
                                        bytesPerRow: 0, bitsPerPixel: 0) else {
        throw Failure("could not allocate \(width)x\(height) bitmap")
    }
    NSGraphicsContext.saveGraphicsState()
    defer { NSGraphicsContext.restoreGraphicsState() }
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
    guard let ctx = NSGraphicsContext.current?.cgContext else { throw Failure("no context") }
    ctx.setAllowsAntialiasing(true)
    body(ctx)

    guard let data = bitmap.representation(using: .png, properties: [:]) else {
        throw Failure("PNG encode failed for \(path)")
    }
    try data.write(to: URL(fileURLWithPath: path))
}

private struct Failure: Error, CustomStringConvertible {
    let description: String
    init(_ description: String) { self.description = description }
}

private func text(_ string: String, size: CGFloat, weight: NSFont.Weight, color: NSColor,
                  at point: CGPoint, tracking: CGFloat = 0) {
    let attributes: [NSAttributedString.Key: Any] = [
        .font: NSFont.systemFont(ofSize: size, weight: weight),
        .foregroundColor: color,
        .kern: tracking,
    ]
    NSAttributedString(string: string, attributes: attributes).draw(at: point)
}

private func textWidth(_ string: String, size: CGFloat, weight: NSFont.Weight,
                       tracking: CGFloat = 0) -> CGFloat {
    NSAttributedString(string: string, attributes: [
        .font: NSFont.systemFont(ofSize: size, weight: weight),
        .kern: tracking,
    ]).size().width
}

// MARK: - Shared artwork

/// A window: white face, chrome strip, optional traffic lights and text lines.
///
/// `detailed` is false for the small icon sizes, where dots and text lines
/// collapse into a few grey pixels of noise instead of reading as a window.
private func drawWindow(_ ctx: CGContext, in rect: CGRect, radius: CGFloat, chromeHeight: CGFloat,
                        detailed: Bool, shadow: Bool = true) {
    let draw = { (ctx: CGContext) in fill(ctx, rounded(rect, radius), Palette.windowFace) }
    if shadow {
        shadowed(ctx, offset: CGSize(width: 0, height: -rect.height * 0.05),
                 blur: rect.height * 0.10, alpha: 0.35, draw)
    } else {
        draw(ctx)
    }

    ctx.saveGState()
    ctx.addPath(rounded(rect, radius))
    ctx.clip()
    fill(ctx, CGPath(rect: CGRect(x: rect.minX, y: rect.maxY - chromeHeight,
                                  width: rect.width, height: chromeHeight), transform: nil),
         Palette.windowChrome)

    if detailed {
        let dot = chromeHeight * 0.38
        for (i, color) in [rgb(255, 95, 87), rgb(254, 188, 46), rgb(40, 200, 64)].enumerated() {
            let x = rect.minX + chromeHeight * 0.5 + CGFloat(i) * dot * 1.62
            let y = rect.maxY - chromeHeight / 2 - dot / 2
            fill(ctx, CGPath(ellipseIn: CGRect(x: x, y: y, width: dot, height: dot), transform: nil), color)
        }
        for (i, fraction) in [0.62, 0.50, 0.39].enumerated() {
            let h = rect.height * 0.068
            let y = rect.maxY - chromeHeight - rect.height * 0.20 - CGFloat(i) * h * 2.4
            fill(ctx, rounded(CGRect(x: rect.minX + rect.width * 0.095, y: y,
                                     width: rect.width * fraction, height: h), h / 2),
                 Palette.windowText)
        }
    }
    ctx.restoreGState()
}

/// The pin, tip planted at `tip`, leaning right.
private func drawPin(_ ctx: CGContext, tip: CGPoint, scale: CGFloat, tilt: CGFloat = -0.36,
                     color: CGColor = Palette.pin, shadow: Bool = true) {
    ctx.saveGState()
    ctx.translateBy(x: tip.x, y: tip.y)
    ctx.rotate(by: tilt)
    let draw = { (ctx: CGContext) in fill(ctx, PinGlyph.path(scale: scale), color) }
    if shadow {
        shadowed(ctx, offset: CGSize(width: 0, height: -12 * scale),
                 blur: 24 * scale, alpha: 0.45, draw)
    } else {
        draw(ctx)
    }
    ctx.restoreGState()
}

// MARK: - App icon

/// Draws the icon into a 1024×1024 coordinate space; callers scale the context.
///
/// `pixelSize` is the real output size and drives how much detail survives —
/// at 32px the window chrome dots are sub-pixel, so they are dropped and the
/// remaining shapes are enlarged rather than shrunk into mud.
private func drawAppIcon(_ ctx: CGContext, pixelSize: Int) {
    let detailed = pixelSize >= 128
    let plateRect = CGRect(x: 100, y: 108, width: 824, height: 824)
    let plate = squircle(in: plateRect)

    shadowed(ctx, offset: CGSize(width: 0, height: -16), blur: 34, alpha: 0.28) { ctx in
        fill(ctx, plate, CGColor(gray: 0, alpha: 1))
    }

    ctx.saveGState()
    ctx.addPath(plate)
    ctx.clip()
    linearGradient(ctx, in: plateRect, Palette.plateTop, Palette.plateBottom)

    // Light wash along the top edge, the way system icon plates catch light.
    let gloss = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                           colors: [CGColor(gray: 1, alpha: 0.26), CGColor(gray: 1, alpha: 0)] as CFArray,
                           locations: [0, 1])!
    ctx.drawLinearGradient(gloss,
                           start: CGPoint(x: 0, y: plateRect.maxY),
                           end: CGPoint(x: 0, y: plateRect.midY + 60),
                           options: [])

    if detailed {
        drawWindow(ctx, in: CGRect(x: 236, y: 300, width: 480, height: 380),
                   radius: 46, chromeHeight: 84, detailed: true)
        drawPin(ctx, tip: CGPoint(x: 652, y: 566), scale: 1.5)
    } else {
        // Same composition, fewer and larger parts.
        drawWindow(ctx, in: CGRect(x: 214, y: 316, width: 540, height: 392),
                   radius: 52, chromeHeight: 96, detailed: false)
        drawPin(ctx, tip: CGPoint(x: 676, y: 574), scale: 1.85)
    }
    ctx.restoreGState()

    // Hairline rim so the plate edge stays crisp on light and dark backgrounds.
    ctx.addPath(plate)
    ctx.setStrokeColor(CGColor(gray: 1, alpha: 0.18))
    ctx.setLineWidth(4)
    ctx.strokePath()
}

private func writeIconset(to directory: String) throws {
    let fm = FileManager.default
    try? fm.removeItem(atPath: directory)
    try fm.createDirectory(atPath: directory, withIntermediateDirectories: true)

    // The set macOS expects: each point size at 1x and 2x.
    let pointSizes = [16, 32, 128, 256, 512]
    for points in pointSizes {
        for scale in [1, 2] {
            let pixels = points * scale
            let name = scale == 1 ? "icon_\(points)x\(points).png" : "icon_\(points)x\(points)@2x.png"
            try renderPNG(width: pixels, height: pixels, to: "\(directory)/\(name)") { ctx in
                ctx.scaleBy(x: CGFloat(pixels) / 1024, y: CGFloat(pixels) / 1024)
                drawAppIcon(ctx, pixelSize: pixels)
            }
        }
    }
}

// MARK: - README figures

/// Wide title card: the icon, the name, and what the app is in one line.
private func writeHero(to path: String) throws {
    let width = 1280, height = 400
    try renderPNG(width: width, height: height, to: path) { ctx in
        let bounds = CGRect(x: 0, y: 0, width: CGFloat(width), height: CGFloat(height))
        linearGradient(ctx, in: bounds, Palette.heroTop, Palette.heroBottom)

        // Faint pin watermark bleeding off the right edge.
        ctx.saveGState()
        ctx.addPath(CGPath(rect: bounds, transform: nil))
        ctx.clip()
        drawPin(ctx, tip: CGPoint(x: 1046, y: 12), scale: 1.45, tilt: -0.36,
                color: CGColor(gray: 1, alpha: 0.055), shadow: false)
        ctx.restoreGState()

        ctx.saveGState()
        ctx.translateBy(x: 96, y: 72)
        ctx.scaleBy(x: 256.0 / 1024, y: 256.0 / 1024)
        drawAppIcon(ctx, pixelSize: 256)
        ctx.restoreGState()

        text("Window Pin", size: 68, weight: .bold, color: .white,
             at: CGPoint(x: 392, y: 214), tracking: -1.4)
        text("Hold any app's window in place — and float your own panel on top.",
             size: 27, weight: .regular, color: NSColor(white: 1, alpha: 0.68),
             at: CGPoint(x: 394, y: 162))

        // Capability chips.
        var x: CGFloat = 394
        for label in ["Accessibility", "ScreenCaptureKit", "WebKit", "Swift 6"] {
            let w = textWidth(label, size: 19, weight: .medium) + 34
            let chip = CGRect(x: x, y: 86, width: w, height: 42)
            fill(ctx, rounded(chip, 21), CGColor(gray: 1, alpha: 0.10))
            ctx.addPath(rounded(chip, 21))
            ctx.setStrokeColor(CGColor(gray: 1, alpha: 0.18))
            ctx.setLineWidth(1.5)
            ctx.strokePath()
            text(label, size: 19, weight: .medium, color: NSColor(white: 1, alpha: 0.80),
                 at: CGPoint(x: x + 17, y: 98))
            x += w + 14
        }
    }
}

/// What the two halves actually do, on one screen.
private func writeHalves(to path: String) throws {
    let width = 1280, height = 620
    try renderPNG(width: width, height: height, to: path) { ctx in
        let bounds = CGRect(x: 0, y: 0, width: CGFloat(width), height: CGFloat(height))
        fill(ctx, CGPath(rect: bounds, transform: nil), Palette.desktop)

        // The display.
        let screen = CGRect(x: 64, y: 108, width: 1152, height: 452)
        shadowed(ctx, offset: CGSize(width: 0, height: -14), blur: 40, alpha: 0.16) { ctx in
            fill(ctx, rounded(screen, 22), rgb(246, 247, 251))
        }
        ctx.saveGState()
        ctx.addPath(rounded(screen, 22))
        ctx.clip()
        linearGradient(ctx, in: screen, rgb(206, 216, 238), rgb(233, 237, 247), diagonal: false)

        // Menu bar, with the app's own status item in it.
        let menuBar = CGRect(x: screen.minX, y: screen.maxY - 34, width: screen.width, height: 34)
        fill(ctx, CGPath(rect: menuBar, transform: nil), CGColor(gray: 1, alpha: 0.72))
        drawPin(ctx, tip: CGPoint(x: screen.maxX - 60, y: menuBar.minY + 8), scale: 0.115,
                tilt: 0, color: Palette.ink, shadow: false)

        // The window you are actually working in.
        drawWindow(ctx, in: CGRect(x: screen.minX + 56, y: screen.minY + 74,
                                   width: 560, height: 292),
                   radius: 16, chromeHeight: 34, detailed: true)

        // Half one: another app's window, held in the corner.
        let pinned = CGRect(x: screen.maxX - 348, y: screen.minY + 46, width: 292, height: 236)
        drawWindow(ctx, in: pinned, radius: 16, chromeHeight: 32, detailed: true)
        drawPin(ctx, tip: CGPoint(x: pinned.maxX - 26, y: pinned.maxY - 16), scale: 0.30)

        // Half two: the floating panel, sitting above everything.
        let panel = CGRect(x: screen.minX + 316, y: screen.minY + 168, width: 300, height: 210)
        shadowed(ctx, offset: CGSize(width: 0, height: -12), blur: 30, alpha: 0.30) { ctx in
            fill(ctx, rounded(panel, 16), rgb(30, 34, 48))
        }
        fill(ctx, rounded(CGRect(x: panel.minX, y: panel.maxY - 30, width: panel.width, height: 30), 16),
             CGColor(gray: 1, alpha: 0.10))
        // A play triangle, standing in for dropped media.
        let play = CGMutablePath()
        play.move(to: CGPoint(x: panel.midX - 20, y: panel.midY - 30))
        play.addLine(to: CGPoint(x: panel.midX + 30, y: panel.midY - 4))
        play.addLine(to: CGPoint(x: panel.midX - 20, y: panel.midY + 22))
        play.closeSubpath()
        fill(ctx, play, CGColor(gray: 1, alpha: 0.85))
        ctx.restoreGState()

        // Captions, tied to what they describe.
        func caption(_ title: String, _ body: String, x: CGFloat, y: CGFloat) {
            text(title, size: 25, weight: .semibold, color: NSColor(cgColor: Palette.ink)!,
                 at: CGPoint(x: x, y: y + 30))
            text(body, size: 19, weight: .regular, color: NSColor(white: 0.42, alpha: 1),
                 at: CGPoint(x: x, y: y))
        }
        caption("Floating Panel", "Always on top. Drop a link, image, PDF or a live window mirror.",
                x: 64, y: 34)
        caption("Pin", "Another app's window, locked to a frame.", x: 782, y: 34)
    }
}

// MARK: - Entry point

@main
enum MakeAssets {
    static func main() {
        let arguments = CommandLine.arguments
        guard arguments.count > 1 else {
            FileHandle.standardError.write("usage: make-assets <output-root>\n".data(using: .utf8)!)
            exit(2)
        }
        let root = arguments[1]

        do {
            try FileManager.default.createDirectory(atPath: "\(root)/docs/images",
                                                    withIntermediateDirectories: true)
            try writeIconset(to: "\(root)/Resources/AppIcon.iconset")
            try writeHero(to: "\(root)/docs/images/hero.png")
            try writeHalves(to: "\(root)/docs/images/overview.png")
            print("assets: iconset, docs/images/hero.png, docs/images/overview.png")
        } catch {
            FileHandle.standardError.write("error: \(error)\n".data(using: .utf8)!)
            exit(1)
        }
    }
}
