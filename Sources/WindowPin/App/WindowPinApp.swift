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

    var body: some Scene {
        MenuBarExtra(isInserted: $canRun) {
            MenuBarView(
                onToggleFloatingPanel: { controllerPanel.toggle(model: model) },
                onToggleContentPanel: { contentPanel.toggle(model: panelModel) }
            )
            .environment(model)
            .environment(panelModel)
        } label: {
            MenuBarIcon(model: model)
        }
        .menuBarExtraStyle(.window)
    }
}
