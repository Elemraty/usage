import Cocoa
import WebKit

/// Opens an embedded browser window pointed at a login page, watches the cookie jar for
/// that site, and hands back the relevant cookies once it looks like login succeeded
/// (or immediately if the user clicks "Save now").
final class LoginWindowController: NSWindowController, NSWindowDelegate {
    private let webView: WKWebView
    private let domainSubstring: String
    /// Name (or name prefix) of the cookie that actually proves login — e.g. "sessionKey"
    /// for claude.ai. Matching on a loose "contains session" instead is a trap: claude.ai
    /// sets `activitySessionId` for logged-out visitors too, which made this window close
    /// instantly and report a connection that had no authorization behind it.
    private let requiredCookiePrefix: String
    private var pollTimer: Timer?
    private var onCookies: (([HTTPCookie]) -> Void)?
    private var statusLabel: NSTextField!

    init(title: String, url: URL, domainSubstring: String, requiredCookiePrefix: String,
         onCookies: @escaping ([HTTPCookie]) -> Void) {
        self.domainSubstring = domainSubstring
        self.requiredCookiePrefix = requiredCookiePrefix
        self.onCookies = onCookies

        let config = WKWebViewConfiguration()
        config.websiteDataStore = .default()
        webView = WKWebView(frame: .zero, configuration: config)
        webView.translatesAutoresizingMaskIntoConstraints = false

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 600, height: 720),
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = title
        window.center()

        super.init(window: window)

        let container = NSView(frame: window.contentView!.bounds)
        container.translatesAutoresizingMaskIntoConstraints = false

        let bar = NSStackView()
        bar.orientation = .horizontal
        bar.spacing = 8
        bar.edgeInsets = NSEdgeInsets(top: 8, left: 12, bottom: 8, right: 12)
        bar.translatesAutoresizingMaskIntoConstraints = false

        // Google refuses OAuth inside embedded web views, so "Google로 계속하기" will fail
        // here no matter what — steer people to the email path (or the paste-cookie menu item).
        statusLabel = NSTextField(labelWithString: "이 창에서 로그인하면 자동 감지됩니다. Google 로그인은 내장 창에서 차단되니 '이메일로 계속하기'를 쓰세요.")
        statusLabel.font = .systemFont(ofSize: 11)
        statusLabel.textColor = .secondaryLabelColor
        statusLabel.lineBreakMode = .byWordWrapping
        statusLabel.maximumNumberOfLines = 2
        statusLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        let saveButton = NSButton(title: "로그인 완료 — 지금 저장", target: self, action: #selector(saveNow))
        saveButton.bezelStyle = .rounded

        bar.addArrangedSubview(statusLabel)
        bar.addArrangedSubview(NSView()) // spacer
        bar.addArrangedSubview(saveButton)

        let rootStack = NSStackView(views: [webView, bar])
        rootStack.orientation = .vertical
        rootStack.spacing = 0
        rootStack.translatesAutoresizingMaskIntoConstraints = false

        window.contentView = rootStack
        NSLayoutConstraint.activate([
            webView.widthAnchor.constraint(equalTo: rootStack.widthAnchor),
            bar.widthAnchor.constraint(equalTo: rootStack.widthAnchor)
        ])

        webView.load(URLRequest(url: url))
        window.delegate = self
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) not implemented") }

    func showAndWatch() {
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        pollTimer?.invalidate()
        pollTimer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { [weak self] _ in
            self?.checkCookiesAutomatically()
        }
    }

    private func checkCookiesAutomatically() {
        relevantCookies { [weak self] relevant in
            guard let self = self else { return }
            if self.hasAuthCookie(relevant) {
                self.statusLabel.stringValue = "로그인 확인됨 — 저장 중…"
                self.finish(cookies: relevant)
            }
        }
    }

    @objc private func saveNow() {
        relevantCookies { [weak self] relevant in
            guard let self = self else { return }
            guard self.hasAuthCookie(relevant) else {
                self.statusLabel.stringValue = "아직 로그인되지 않았습니다 (\(self.requiredCookiePrefix) 쿠키 없음). 로그인을 완료해 주세요."
                return
            }
            self.finish(cookies: relevant)
        }
    }

    private func relevantCookies(_ handler: @escaping ([HTTPCookie]) -> Void) {
        webView.configuration.websiteDataStore.httpCookieStore.getAllCookies { [weak self] cookies in
            guard let self = self else { return }
            handler(cookies.filter { $0.domain.contains(self.domainSubstring) })
        }
    }

    private func hasAuthCookie(_ cookies: [HTTPCookie]) -> Bool {
        cookies.contains { $0.name.hasPrefix(requiredCookiePrefix) && !$0.value.isEmpty }
    }

    private func finish(cookies: [HTTPCookie]) {
        pollTimer?.invalidate()
        pollTimer = nil
        let callback = onCookies
        onCookies = nil
        callback?(cookies)
        close()
    }

    func windowWillClose(_ notification: Notification) {
        pollTimer?.invalidate()
        pollTimer = nil
    }
}
