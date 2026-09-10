import AppKit
import SwiftUI

/// The always-on-top window that holds dropped content.
///
/// This is where the app can genuinely deliver "stays above everything":
/// the panel belongs to us, so setting `level` is allowed — unlike another
/// application's window, whose level macOS exposes no public API for.
@MainActor
final class FloatingContentPanel {
    private var panel: NSPanel?

    func toggle(model: PanelModel) {
        if let panel, panel.isVisible {
            panel.orderOut(nil)
        } else {
            show(model: model)
        }
    }

    /// Height of the panel's own toolbar row, excluded from aspect-ratio maths.
    private static let toolbarHeight: CGFloat = 30

    func show(model: PanelModel) {
        let panel = self.panel ?? makePanel(model: model)
        self.panel = panel
        model.onAspectRatio = { [weak self] size in
            self?.matchAspectRatio(size)
        }
        panel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    /// Reshapes the panel to the mirrored window's proportions.
    ///
    /// Without this a wide browser window inside a squarish panel is letterboxed
    /// down to a fraction of the available area — the video ends up tiny with
    /// black bars above and below it.
    private func matchAspectRatio(_ size: CGSize?) {
        guard let panel else { return }
        guard let size, size.width > 0, size.height > 0 else {
            panel.resizeIncrements = NSSize(width: 1, height: 1)
            return
        }

        var frame = panel.frame
        let chrome = frame.height - panel.contentLayoutRect.height + Self.toolbarHeight
        let contentWidth = frame.width
        let newHeight = (contentWidth * size.height / size.width) + chrome

        // Grow upward from the current bottom edge, then pull back on-screen if
        // that pushed the title bar off the top.
        frame.size.height = newHeight
        if let visible = panel.screen?.visibleFrame {
            frame.size.height = min(frame.size.height, visible.height)
            if frame.maxY > visible.maxY { frame.origin.y = visible.maxY - frame.height }
            if frame.minY < visible.minY { frame.origin.y = visible.minY }
        }
        panel.setFrame(frame, display: true, animate: true)
    }

    private func makePanel(model: PanelModel) -> NSPanel {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 420, height: 320),
            styleMask: [.titled, .closable, .resizable, .utilityWindow, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        panel.title = "Window Pin"
        panel.titlebarAppearsTransparent = true
        panel.titleVisibility = .hidden
        panel.contentView = NSHostingView(rootView: PanelRootView().environment(model))
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.isMovableByWindowBackground = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.minSize = NSSize(width: 260, height: 180)

        // Bottom-right of the active display, out of the way of real work.
        if let visible = NSScreen.main?.visibleFrame {
            panel.setFrameOrigin(NSPoint(x: visible.maxX - panel.frame.width - 20,
                                         y: visible.minY + 20))
        }
        return panel
    }
}
