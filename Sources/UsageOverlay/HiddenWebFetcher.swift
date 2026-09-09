import Cocoa
import WebKit

/// Loads a URL in an invisible WKWebView sharing the persistent cookie jar (the same
/// store LoginWindowController signs into), then reads the page text back as JSON.
/// Claude.ai's usage API sits behind Cloudflare bot detection that blocks plain
/// URLSession requests even with correct cookies/headers; routing through a real
/// WebKit view (real TLS/JS fingerprint) is what claude-usage-widget does too.
final class HiddenWebFetcher: NSObject, WKNavigationDelegate {
    private let webView: WKWebView
    private let hostWindow: NSWindow
    private var completion: ((Result<Any, SimpleError>) -> Void)?
    private var timeoutTimer: Timer?
    private var selfRetain: HiddenWebFetcher?

    private override init() {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .default()
        webView = WKWebView(frame: NSRect(x: 0, y: 0, width: 2, height: 2), configuration: config)
        webView.customUserAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.4 Safari/605.1.15"

        // Must stay genuinely on-screen (real position, non-zero alpha) or WindowServer
        // treats it as occluded and macOS suspends the WebContent process entirely —
        // navigation then just hangs forever instead of failing. A near-invisible 2x2
        // dot in the corner is the trade-off: technically "visible", practically not.
        let screenFrame = NSScreen.main?.frame ?? NSRect(x: 0, y: 0, width: 100, height: 100)
        let origin = NSPoint(x: screenFrame.minX, y: screenFrame.minY)
        hostWindow = NSWindow(contentRect: NSRect(origin: origin, size: NSSize(width: 2, height: 2)),
                               styleMask: [.borderless], backing: .buffered, defer: false)
        hostWindow.isReleasedWhenClosed = false
        hostWindow.alphaValue = 0.01
        hostWindow.hasShadow = false
        hostWindow.ignoresMouseEvents = true
        hostWindow.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        hostWindow.contentView = webView

        super.init()
        webView.navigationDelegate = self
    }

    static func fetchJSON(url: URL, timeout: TimeInterval = 25, completion: @escaping (Result<Any, SimpleError>) -> Void) {
        DispatchQueue.main.async {
            let fetcher = HiddenWebFetcher()
            fetcher.completion = completion
            fetcher.selfRetain = fetcher
            fetcher.hostWindow.orderFront(nil)
            fetcher.timeoutTimer = Timer.scheduledTimer(withTimeInterval: timeout, repeats: false) { [weak fetcher] _ in
                fetcher?.finish(.failure(SimpleError(message: "timeout waiting for page")))
            }
            fetcher.webView.load(URLRequest(url: url))
        }
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        webView.evaluateJavaScript("document.body ? document.body.innerText : ''") { [weak self] result, _ in
            guard let self = self else { return }
            guard let text = result as? String, !text.isEmpty else {
                self.finish(.failure(SimpleError(message: "empty page (login may have expired)")))
                return
            }
            if text.contains("Just a moment") || text.contains("Enable JavaScript and cookies") {
                self.finish(.failure(SimpleError(message: "blocked by Cloudflare challenge")))
                return
            }
            guard let data = text.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: data) else {
                self.finish(.failure(SimpleError(message: "page was not JSON (login may have expired)")))
                return
            }
            self.finish(.success(json))
        }
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        finish(.failure(SimpleError(message: error.localizedDescription)))
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        finish(.failure(SimpleError(message: error.localizedDescription)))
    }

    private func finish(_ result: Result<Any, SimpleError>) {
        timeoutTimer?.invalidate()
        timeoutTimer = nil
        let cb = completion
        completion = nil
        hostWindow.orderOut(nil)
        cb?(result)
        selfRetain = nil
    }
}
