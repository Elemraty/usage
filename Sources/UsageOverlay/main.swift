import Cocoa
import WebKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var timer: Timer?
    private var latestResults: [ProviderResult] = []
    private var openLoginWindows: [LoginWindowController] = []
    private var lastUpdated: Date?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.title = "…"

        rebuildMenu(loading: true)
        refresh()
        scheduleTimer()
    }

    private func scheduleTimer() {
        timer?.invalidate()
        let cfg = ConfigStore.load()
        let interval = max(30, cfg.refreshIntervalSeconds)
        timer = Timer.scheduledTimer(withTimeInterval: TimeInterval(interval), repeats: true) { [weak self] _ in
            self?.refresh()
        }
    }

    @objc private func refresh() {
        let cfg = ConfigStore.load()
        let enabled = cfg.providers.filter { $0.enabled }
        guard !enabled.isEmpty else {
            latestResults = []
            lastUpdated = nil
            updateStatusBarTitle()
            rebuildMenu(loading: false)
            return
        }

        var results: [ProviderResult?] = Array(repeating: nil, count: enabled.count)
        let group = DispatchGroup()
        for (i, provider) in enabled.enumerated() {
            group.enter()
            UsageFetcher.fetch(provider) { result in
                results[i] = result
                group.leave()
            }
        }
        group.notify(queue: .main) { [weak self] in
            self?.latestResults = results.compactMap { $0 }
            self?.lastUpdated = Date()
            self?.updateStatusBarTitle()
            self?.rebuildMenu(loading: false)
        }
    }

    /// Compact, colour-coded summary — e.g. "CL 77 · GPT 52". Stays in the normal menu bar
    /// colour while there's headroom and only turns amber/red when a limit is running out,
    /// so it reads as a quiet indicator rather than a permanent alert.
    private func updateStatusBarTitle() {
        guard let button = statusItem.button else { return }
        guard !latestResults.isEmpty else {
            button.attributedTitle = NSAttributedString(
                string: "Usage",
                attributes: [.font: NSFont.systemFont(ofSize: 12, weight: .medium)]
            )
            return
        }

        let title = NSMutableAttributedString()
        for (index, result) in latestResults.enumerated() {
            if index > 0 {
                title.append(NSAttributedString(string: "  ", attributes: [
                    .font: NSFont.systemFont(ofSize: 12),
                    .foregroundColor: NSColor.tertiaryLabelColor
                ]))
            }
            title.append(NSAttributedString(string: shortName(result.name) + " ", attributes: [
                .font: NSFont.systemFont(ofSize: 10, weight: .medium),
                .foregroundColor: NSColor.secondaryLabelColor
            ]))

            let valueText: String
            var valueColor = NSColor.labelColor
            if let percent = result.primary.percent {
                let remaining = 100 - Int(percent.rounded())
                valueText = "\(remaining)"
                if remaining < 40 { valueColor = MenuTheme.levelColor(remaining: remaining) }
            } else {
                valueText = "–"
                valueColor = .tertiaryLabelColor
            }
            title.append(NSAttributedString(string: valueText, attributes: [
                .font: NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .semibold),
                .foregroundColor: valueColor
            ]))
        }
        button.attributedTitle = title
    }

    private func shortName(_ providerName: String) -> String {
        ConfigStore.loadRaw().providers.first { $0.name == providerName }?.shortName
            ?? String(providerName.prefix(2)).uppercased()
    }

    private func rebuildMenu(loading: Bool) {
        let menu = NSMenu()

        if loading {
            menu.addItem(row(MessageRowView(text: "불러오는 중…", color: .secondaryLabelColor)))
        } else if latestResults.isEmpty {
            menu.addItem(row(MessageRowView(text: "연결된 서비스가 없습니다. 아래에서 로그인하세요.",
                                             symbolName: "person.crop.circle.badge.questionmark",
                                             color: .secondaryLabelColor)))
        } else {
            for result in latestResults {
                menu.addItem(row(ProviderHeaderView(title: result.name)))
                menu.addItem(row(usageRow(result.primary)))
                if let secondary = result.secondary {
                    menu.addItem(row(usageRow(secondary)))
                }
                if let error = result.error {
                    menu.addItem(row(MessageRowView(text: error,
                                                     symbolName: "exclamationmark.triangle.fill",
                                                     color: .systemOrange)))
                }
            }
            if let updated = lastUpdated {
                menu.addItem(NSMenuItem.separator())
                menu.addItem(row(MessageRowView(text: "\(relativeString(updated)) 업데이트",
                                                 color: .tertiaryLabelColor)))
            }
        }

        menu.addItem(NSMenuItem.separator())
        menu.addItem(action("지금 새로고침", #selector(refresh), symbol: "arrow.clockwise", key: "r"))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(action(loginTitle(for: "Claude"), #selector(loginClaude), symbol: "person.crop.circle"))
        menu.addItem(action("Claude sessionKey 붙여넣기…", #selector(pasteClaudeSessionKey), symbol: "key"))
        menu.addItem(action(loginTitle(for: "ChatGPT"), #selector(loginChatGPT), symbol: "person.crop.circle"))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(action("설정 폴더 열기", #selector(openConfigFolder), symbol: "folder"))
        menu.addItem(action("종료", #selector(quit), symbol: "power", key: "q"))

        statusItem.menu = menu
    }

    private func usageRow(_ window: UsageWindow) -> UsageRowView {
        // The APIs report percent *used*; both official apps show percent *remaining*.
        let remaining = window.percent.map { 100 - Int($0.rounded()) }
        let resetText = window.resetsAt.map { "\(absoluteString($0)) 리셋" }
        return UsageRowView(label: window.label, remaining: remaining, resetText: resetText)
    }

    /// Wraps a custom view in a non-interactive menu item.
    private func row(_ view: NSView) -> NSMenuItem {
        let item = NSMenuItem()
        item.view = view
        return item
    }

    private func action(_ title: String, _ selector: Selector, symbol: String, key: String = "") -> NSMenuItem {
        let item = NSMenuItem(title: title, action: selector, keyEquivalent: key)
        item.target = self
        let config = NSImage.SymbolConfiguration(pointSize: 12, weight: .regular)
        item.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)?
            .withSymbolConfiguration(config)
        return item
    }

    private func relativeString(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        formatter.locale = .current
        return formatter.localizedString(for: date, relativeTo: Date())
    }

    /// "오후 1:40" for today, "9월 7일 오후 1:40" otherwise — matching how Claude's and
    /// ChatGPT's own usage panels print their reset times.
    private func absoluteString(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = .current
        if Calendar.current.isDate(date, inSameDayAs: Date()) {
            formatter.dateStyle = .none
            formatter.timeStyle = .short
        } else {
            formatter.setLocalizedDateFormatFromTemplate("MMMd jm")
        }
        return formatter.string(from: date)
    }

    @objc private func openConfigFolder() {
        NSWorkspace.shared.open(ConfigStore.dir)
    }

    private func loginTitle(for providerName: String) -> String {
        let connected = ConfigStore.isProviderEnabled(name: providerName)
        return connected ? "\(providerName) 로그인… (연결됨, 다시 로그인)" : "\(providerName) 로그인…"
    }

    @objc private func loginClaude() {
        openLogin(
            providerName: "Claude",
            windowTitle: "Claude 로그인",
            url: URL(string: "https://claude.ai/login")!,
            domainSubstring: "claude.ai",
            requiredCookiePrefix: "sessionKey",
            secretKey: "claude_cookie"
        )
    }

    @objc private func loginChatGPT() {
        openLogin(
            providerName: "ChatGPT",
            windowTitle: "ChatGPT 로그인",
            url: URL(string: "https://chatgpt.com")!,
            domainSubstring: "chatgpt.com",
            // chatgpt.com splits its session token across "…session-token.0" / ".1".
            requiredCookiePrefix: "__Secure-next-auth.session-token",
            secretKey: "chatgpt_cookie"
        )
    }

    private func openLogin(providerName: String, windowTitle: String, url: URL, domainSubstring: String,
                            requiredCookiePrefix: String, secretKey: String) {
        let buildSecret: ([HTTPCookie]) -> String = { cookies in
            cookies.map { "\($0.name)=\($0.value)" }.joined(separator: "; ")
        }
        let controller = LoginWindowController(title: windowTitle, url: url, domainSubstring: domainSubstring,
                                                requiredCookiePrefix: requiredCookiePrefix) { [weak self] cookies in
            guard let self = self else { return }
            let secretValue = buildSecret(cookies)
            ConfigStore.setSecret(secretKey, secretValue)
            ConfigStore.setProviderEnabled(name: providerName, enabled: true)
            self.openLoginWindows.removeAll { $0.window == nil }
            self.refresh()
            self.showBriefAlert(title: "\(providerName) 연결됨", message: "사용량을 불러오는 중입니다. 메뉴바를 확인하세요.")
        }
        openLoginWindows.append(controller)
        controller.showAndWatch()
    }

    /// Google blocks its OAuth flow inside embedded web views, so Google-linked accounts
    /// can't finish the in-app login. They can instead sign in with their normal browser
    /// and paste the `sessionKey` cookie value here.
    @objc private func pasteClaudeSessionKey() {
        let alert = NSAlert()
        alert.messageText = "Claude sessionKey 붙여넣기"
        alert.informativeText = """
        평소 쓰는 브라우저에서 claude.ai에 로그인한 뒤:
        개발자 도구(⌥⌘I) → Application/Storage → Cookies → https://claude.ai
        → sessionKey 행의 Value를 복사해서 아래에 붙여넣으세요.
        """
        alert.alertStyle = .informational
        alert.addButton(withTitle: "저장")
        alert.addButton(withTitle: "취소")

        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 380, height: 24))
        field.placeholderString = "sk-ant-sid01-…"
        alert.accessoryView = field
        alert.window.initialFirstResponder = field

        NSApp.activate(ignoringOtherApps: true)
        guard alert.runModal() == .alertFirstButtonReturn else { return }

        let value = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return }

        CookieInjector.set(name: "sessionKey", value: value, domain: ".claude.ai") { [weak self] ok in
            guard let self = self else { return }
            guard ok else {
                self.showBriefAlert(title: "저장 실패", message: "쿠키를 저장하지 못했습니다.")
                return
            }
            ConfigStore.setSecret("claude_cookie", "sessionKey=\(value)")
            ConfigStore.setProviderEnabled(name: "Claude", enabled: true)
            self.refresh()
            self.showBriefAlert(title: "Claude 연결됨", message: "사용량을 불러오는 중입니다. 메뉴바를 확인하세요.")
        }
    }

    private func showBriefAlert(title: String, message: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.alertStyle = .informational
        alert.runModal()
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}

let app = NSApplication.shared

// Dev affordance: render the dropdown's rows to a PNG and exit, so the layout can be
// reviewed without opening the menu by hand.
if let flagIndex = CommandLine.arguments.firstIndex(of: "--render-preview"),
   CommandLine.arguments.count > flagIndex + 1 {
    MenuPreview.render(to: CommandLine.arguments[flagIndex + 1])
    exit(0)
}

let delegate = AppDelegate()
app.delegate = delegate
app.run()
