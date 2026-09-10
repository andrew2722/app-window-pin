import AppKit
import SwiftUI

/// Owns the layer that mirrored frames are drawn into, and the input path back
/// to the mirrored window.
///
/// Frames arrive ~30 times a second. Routing them through SwiftUI state would
/// rebuild the view tree at that rate, so the layer is updated directly and
/// SwiftUI only ever sees a stable `NSView`.
@MainActor
final class MirrorRenderer {
    let view = MirrorSurfaceNSView()

    func present(_ frame: MirrorFrame) {
        view.present(frame.surface)
    }

    func clear() {
        view.clear()
    }

    /// Tells the view how large the captured window is, so it can letterbox
    /// correctly and translate clicks back into window coordinates.
    func setSourceSize(_ size: CGSize) {
        view.sourceSize = size
    }
}

/// Layer-backed view showing the captured `IOSurface`, and the first half of
/// the input path: it turns local mouse/key events into window-relative ones.
final class MirrorSurfaceNSView: NSView {
    /// Size of the mirrored window, in its own coordinates.
    var sourceSize: CGSize = .zero

    /// Keys are forwarded to the mirrored app; a click asks to jump to the
    /// real window, because synthetic clicks cannot be delivered.
    var onKey: ((NSEvent) -> Void)?
    var onActivateRequest: (() -> Void)?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        configure()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("MirrorSurfaceNSView is created in code only")
    }

    private func configure() {
        wantsLayer = true
        // Letterbox rather than distort: a mirrored window rarely matches the
        // panel's aspect ratio, and stretching text looks broken.
        layer?.contentsGravity = .resizeAspect
        layer?.backgroundColor = NSColor.black.cgColor
    }

    func present(_ surface: IOSurfaceRef) {
        // Assigning an IOSurface directly is the zero-copy path; Core Animation
        // retains it for as long as it is displayed.
        layer?.contents = surface
    }

    func clear() {
        layer?.contents = nil
    }

    // MARK: - Input

    override var acceptsFirstResponder: Bool { true }

    /// Take keyboard focus as soon as the panel shows us, so playback keys work
    /// without the user having to click first.
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        window?.makeFirstResponder(self)
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDown(with event: NSEvent) {
        onActivateRequest?()
    }

    override func keyDown(with event: NSEvent) {
        onKey?(event)
    }

    override func keyUp(with event: NSEvent) {
        onKey?(event)
    }
}

/// Bridges the renderer's `NSView` into SwiftUI.
struct MirrorSurfaceView: NSViewRepresentable {
    let renderer: MirrorRenderer

    func makeNSView(context: Context) -> MirrorSurfaceNSView {
        renderer.view
    }

    func updateNSView(_ nsView: MirrorSurfaceNSView, context: Context) {}
}
