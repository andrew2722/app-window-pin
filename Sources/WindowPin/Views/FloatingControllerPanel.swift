import AppKit
import SwiftUI

/// A detachable copy of the controller in an `NSPanel`.
///
/// The menu bar popover closes as soon as you click another app, which is
/// awkward while arranging windows. A non-activating floating panel stays put
/// and does not steal focus from the app whose window is being positioned.
@MainActor
final class FloatingControllerPanel {
    private var panel: NSPanel?

    func toggle(model: AppModel, updates: UpdateService) {
        if let panel, panel.isVisible {
            panel.orderOut(nil)
        } else {
            show(model: model, updates: updates)
        }
    }

    func show(model: AppModel, updates: UpdateService) {
        let panel = self.panel ?? makePanel(model: model, updates: updates)
        self.panel = panel
        panel.orderFrontRegardless()
    }

    private func makePanel(model: AppModel, updates: UpdateService) -> NSPanel {
        let content = ControllerView(showsFloatingPanelButton: false)
            .environment(model)
            .environment(updates)

        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 320, height: 520),
            // `.nonactivatingPanel` is what lets the user click our buttons
            // without making Window Pin the frontmost app.
            styleMask: [.titled, .closable, .utilityWindow, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.title = "Window Pin"
        panel.contentView = NSHostingView(rootView: content)
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.center()
        return panel
    }
}
