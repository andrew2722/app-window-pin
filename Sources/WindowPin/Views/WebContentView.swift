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
        HStack(spacing: 4) {
            Button { session.goBack() } label: { Image(systemName: "chevron.left") }
                .disabled(!session.canGoBack)
                .help("Back")

            Button { session.goForward() } label: { Image(systemName: "chevron.right") }
                .disabled(!session.canGoForward)
                .help("Forward")

            Button { session.reloadOrStop() } label: {
                Image(systemName: session.isLoading ? "xmark" : "arrow.clockwise")
            }
            .help(session.isLoading ? "Stop" : "Reload")

            TextField("Enter a link or search", text: $session.addressText)
                .textFieldStyle(.roundedBorder)
                .font(.caption)
                .focused($addressFocused)
                .onSubmit {
                    onSubmit()
                    addressFocused = false
                }

            Button(action: onMirrorInstead) {
                Image(systemName: "macwindow.on.rectangle")
            }
            .help("Signed-in page? Mirror the real browser window instead")
        }
        .buttonStyle(.borderless)
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
    }
}
