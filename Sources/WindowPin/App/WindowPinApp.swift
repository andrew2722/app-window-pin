import SwiftUI

/// Menu-bar-only utility (`LSUIElement` in Info.plist), so there is no Dock
/// icon and no main window — the menu bar item is the whole app.
///
/// Two independent halves share it:
/// - **Pin**: holds another app's existing window at a fixed frame (Accessibility).
/// - **Panel**: a floating always-on-top box you drop content into (ScreenCaptureKit).
@main
struct WindowPinApp: App {
    /// Runs before any model is built: a translocated launch has to stop here,
    /// because permissions granted to a randomised path cannot survive.
    @State private var canRun = LaunchGuard.check()
    @State private var model = AppModel()
    @State private var panelModel = PanelModel()
    @State private var controllerPanel = FloatingControllerPanel()
    @State private var contentPanel = FloatingContentPanel()
    /// Built after `LaunchGuard`: a translocated copy is about to move itself
    /// and relaunch, and must not start an updater that would then be checking
    /// on behalf of a bundle that is going away.
    @State private var updates = UpdateService()

    var body: some Scene {
        MenuBarExtra(isInserted: $canRun) {
            MenuBarView(
                onToggleFloatingPanel: { controllerPanel.toggle(model: model, updates: updates) },
                onToggleContentPanel: { contentPanel.toggle(model: panelModel) }
            )
            .environment(model)
            .environment(panelModel)
            .environment(updates)
        } label: {
            MenuBarIcon(model: model, hasUpdate: updates.pendingVersion != nil)
        }
        .menuBarExtraStyle(.window)
    }
}
