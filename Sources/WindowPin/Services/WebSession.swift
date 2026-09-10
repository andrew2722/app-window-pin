import Observation
import WebKit

/// A live web page inside the panel.
///
/// This is the interactive counterpart to mirroring: a real `WKWebView` accepts
/// clicks, scrolling and typing, which a ScreenCaptureKit mirror cannot. The
/// trade-off is that it has its own cookie store, so sessions you are logged
/// into in Chrome are not shared here.
@MainActor
@Observable
final class WebSession: NSObject, WKNavigationDelegate, WKUIDelegate {
    /// Appended to WebKit's default user agent so sites treat the panel as a
    /// current Safari rather than an unknown embedder.
    private static let safariUserAgentSuffix = "Version/18.5 Safari/605.1.15"

    let webView: WKWebView

    private(set) var pageTitle = ""
    private(set) var currentURL: URL?
    private(set) var canGoBack = false
    private(set) var canGoForward = false
    private(set) var isLoading = false
    /// Last navigation failure, so a dead link does not just leave a blank panel.
    private(set) var loadError: String?

    /// What the address field shows. Kept separate from `currentURL` so typing
    /// is not overwritten mid-edit by a page finishing its load.
    var addressText = ""

    @ObservationIgnored private var observations: [NSKeyValueObservation] = []

    override init() {
        let configuration = WKWebViewConfiguration()
        // Behave like a browser: video should play without an extra gesture,
        // which is the whole point of putting a video site in this panel.
        configuration.mediaTypesRequiringUserActionForPlayback = []
        // Without a Safari version in the user agent, sites decide we are an
        // ancient browser and serve a degraded page — YouTube, for one, refuses
        // to load live chat and shows an "update your browser" notice.
        configuration.applicationNameForUserAgent = Self.safariUserAgentSuffix
        webView = WKWebView(frame: .zero, configuration: configuration)
        super.init()
        webView.allowsBackForwardNavigationGestures = true
        webView.navigationDelegate = self
        webView.uiDelegate = self
        observe()
    }

    func load(_ url: URL) {
        // Same allowlist the drop path uses: nothing but ordinary web addresses
        // ever reaches the web view.
        guard DropIntakeService.isSafeWebURL(url) else { return }
        loadError = nil
        addressText = url.absoluteString
        webView.load(URLRequest(url: url))
    }

    func goBack() { webView.goBack() }
    func goForward() { webView.goForward() }

    func reloadOrStop() {
        if isLoading {
            webView.stopLoading()
        } else {
            webView.reload()
        }
    }

    /// Turns whatever the user typed into a URL. Bare hostnames get a scheme;
    /// anything that is not plausibly an address becomes a web search, which is
    /// what a browser address bar does.
    static func resolve(_ text: String) -> URL? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        if let url = URL(string: trimmed), url.scheme == "http" || url.scheme == "https" {
            return url
        }
        // "youtube.com/watch?v=..." or "localhost:3000" — looks like a host, so
        // supply the scheme the user left out.
        let firstComponent = trimmed.split(separator: "/").first.map(String.init) ?? trimmed
        let host = firstComponent.split(separator: ":").first.map(String.init) ?? firstComponent
        let isLoopback = host == "localhost" || host == "127.0.0.1"
        if !trimmed.contains(" "), isLoopback || firstComponent.contains(".") {
            // Local development servers are almost never on https.
            let scheme = isLoopback ? "http" : "https"
            if let url = URL(string: "\(scheme)://\(trimmed)") { return url }
        }
        guard let query = trimmed.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) else {
            return nil
        }
        return URL(string: "https://www.google.com/search?q=\(query)")
    }

    // MARK: - Navigation reporting

    func webView(_ webView: WKWebView,
                             didStartProvisionalNavigation navigation: WKNavigation!) {
        loadError = nil
    }

    func webView(_ webView: WKWebView,
                             didFailProvisionalNavigation navigation: WKNavigation!,
                             withError error: Error) {
        present(error)
    }

    func webView(_ webView: WKWebView,
                             didFail navigation: WKNavigation!,
                             withError error: Error) {
        present(error)
    }

    private func present(_ error: Error) {
        let nsError = error as NSError
        // A cancelled navigation is normal: the user hit stop, or a redirect
        // superseded the request. Reporting it would be noise.
        guard !(nsError.domain == NSURLErrorDomain && nsError.code == NSURLErrorCancelled) else {
            return
        }
        loadError = nsError.localizedDescription
    }

    /// The panel holds a single web view, so a link that asks for a new window
    /// is loaded in place rather than silently doing nothing — which is what
    /// sign-in popups and `target="_blank"` links would otherwise do.
    func webView(_ webView: WKWebView,
                             createWebViewWith configuration: WKWebViewConfiguration,
                             for navigationAction: WKNavigationAction,
                             windowFeatures: WKWindowFeatures) -> WKWebView? {
        if navigationAction.targetFrame == nil, let url = navigationAction.request.url {
            load(url)
        }
        return nil
    }

    /// KVO rather than a navigation delegate: these five properties are exactly
    /// what the toolbar needs, and WebKit updates them on the main thread.
    private func observe() {
        observations = [
            webView.observe(\.title) { [weak self] view, _ in
                MainActor.assumeIsolated { self?.pageTitle = view.title ?? "" }
            },
            webView.observe(\.url) { [weak self] view, _ in
                MainActor.assumeIsolated {
                    self?.currentURL = view.url
                    if let address = view.url?.absoluteString { self?.addressText = address }
                }
            },
            webView.observe(\.canGoBack) { [weak self] view, _ in
                MainActor.assumeIsolated { self?.canGoBack = view.canGoBack }
            },
            webView.observe(\.canGoForward) { [weak self] view, _ in
                MainActor.assumeIsolated { self?.canGoForward = view.canGoForward }
            },
            webView.observe(\.isLoading) { [weak self] view, _ in
                MainActor.assumeIsolated { self?.isLoading = view.isLoading }
            }
        ]
    }
}
