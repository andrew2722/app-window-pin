import SwiftUI
import WebKit

/// Hosts the session's `WKWebView`. The view is owned by `WebSession` so
/// navigation state survives SwiftUI rebuilding the body.
struct WebContentView: NSViewRepresentable {
    let session: WebSession

    func makeNSView(context: Context) -> WKWebView {
        session.webView
    }

    func updateNSView(_ nsView: WKWebView, context: Context) {}
}

/// Address field plus the navigation controls that make the panel usable as a
/// small browser.
struct WebNavigationBar: View {
    @Bindable var session: WebSession
    /// Goes through the panel model rather than the session directly, so
    /// submitting an address also switches the panel into web mode.
    var onSubmit: () -> Void
    /// For pages whose logged-in session lives in the user's real browser
    /// rather than in this web view.
    var onMirrorInstead: () -> Void

    @FocusState private var addressFocused: Bool

    var body: some View {
        HStack(spacing: Theme.Space.xs) {
            IconButton(symbol: "chevron.left", label: "Back") { session.goBack() }
                .disabled(!session.canGoBack)

            IconButton(symbol: "chevron.right", label: "Forward") { session.goForward() }
                .disabled(!session.canGoForward)

            IconButton(symbol: session.isLoading ? "xmark" : "arrow.clockwise",
                       label: session.isLoading ? "Stop" : "Reload") {
                session.reloadOrStop()
            }

            TextField("Enter a link or search", text: $session.addressText)
                .textFieldStyle(.roundedBorder)
                .font(.caption)
                .focused($addressFocused)
                .accessibilityLabel("Address")
                .onSubmit {
                    onSubmit()
                    addressFocused = false
                }

            IconButton(symbol: "macwindow.on.rectangle",
                       label: "Signed-in page? Mirror the real browser window instead",
                       action: onMirrorInstead)
        }
        .padding(.horizontal, Theme.Space.s)
        .padding(.vertical, Theme.Space.xs)
        .background(.bar)
    }
}
