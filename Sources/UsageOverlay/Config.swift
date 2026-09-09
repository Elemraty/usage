import Foundation

struct ProviderConfig: Codable {
    var name: String
    var enabled: Bool = true
    var url: String
    var method: String = "GET"
    var headers: [String: String] = [:]
    var body: String? = nil

    // How to read the "usage" number out of the JSON response.
    // Option A: a single path that already holds a percent (0-100) or fraction (0-1).
    var percentPath: String? = nil
    var percentIsFraction: Bool = false

    // Option B: compute percent from used/limit.
    var usedPath: String? = nil
    var limitPath: String? = nil

    // Optional: when the limit resets.
    var resetAtPath: String? = nil
    // "auto" (default: guesses from the raw value's shape) | "iso8601" | "epochSeconds" | "epochMillis"
    var resetAtFormat: String = "auto"

    var primaryLabel: String = "primary"
    /// Abbreviation shown in the menu bar, where space is tight ("Claude" -> "CL").
    var shortName: String? = nil

    // Optional second window (e.g. Claude has a 5h window and a weekly window).
    var secondaryLabel: String? = nil
    var secondaryPercentPath: String? = nil
    var secondaryPercentIsFraction: Bool = false
    var secondaryResetAtPath: String? = nil
    var secondaryResetAtFormat: String = "auto"

    // If `url` contains the literal token "{organizationId}", it is resolved once
    // (and cached for the process lifetime) by GETing `orgIdURL` with the same
    // headers and reading `orgIdPath` out of the JSON response.
    var orgIdURL: String? = nil
    var orgIdPath: String? = nil

    // Two-step auth: if set, GET `tokenURL` with the current headers (e.g. a
    // session cookie), read `tokenPath` out of the JSON response, then add
    // `tokenHeaderPrefix + token` as header `tokenHeaderName` before the real
    // request. Cached for the process lifetime.
    var tokenURL: String? = nil
    var tokenPath: String? = nil
    var tokenHeaderName: String? = nil
    var tokenHeaderPrefix: String = ""

    // If true, `url` (and `orgIdURL`) are loaded in a hidden, persistent-cookie-jar
    // WKWebView instead of URLSession — needed for sites (Claude.ai) that block
    // plain HTTP clients with a Cloudflare bot challenge even with correct cookies.
    // `headers` is ignored in this mode; the webview sends whatever cookies were
    // saved the last time the user logged in via the menu bar's login button.
    var useHiddenBrowser: Bool = false

    // Decoded leniently: Swift's synthesized Codable ignores property defaults and fails
    // on any missing key, which would wipe a user's config every time a field is added.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let base = ProviderConfig(name: (try? c.decode(String.self, forKey: .name)) ?? "", url: "")
        name = base.name
        enabled = (try? c.decode(Bool.self, forKey: .enabled)) ?? base.enabled
        url = (try? c.decode(String.self, forKey: .url)) ?? base.url
        method = (try? c.decode(String.self, forKey: .method)) ?? base.method
        headers = (try? c.decode([String: String].self, forKey: .headers)) ?? base.headers
        body = try? c.decode(String.self, forKey: .body)
        percentPath = try? c.decode(String.self, forKey: .percentPath)
        percentIsFraction = (try? c.decode(Bool.self, forKey: .percentIsFraction)) ?? base.percentIsFraction
        usedPath = try? c.decode(String.self, forKey: .usedPath)
        limitPath = try? c.decode(String.self, forKey: .limitPath)
        resetAtPath = try? c.decode(String.self, forKey: .resetAtPath)
        resetAtFormat = (try? c.decode(String.self, forKey: .resetAtFormat)) ?? base.resetAtFormat
        primaryLabel = (try? c.decode(String.self, forKey: .primaryLabel)) ?? base.primaryLabel
        shortName = try? c.decode(String.self, forKey: .shortName)
        secondaryLabel = try? c.decode(String.self, forKey: .secondaryLabel)
        secondaryPercentPath = try? c.decode(String.self, forKey: .secondaryPercentPath)
        secondaryPercentIsFraction = (try? c.decode(Bool.self, forKey: .secondaryPercentIsFraction)) ?? base.secondaryPercentIsFraction
        secondaryResetAtPath = try? c.decode(String.self, forKey: .secondaryResetAtPath)
        secondaryResetAtFormat = (try? c.decode(String.self, forKey: .secondaryResetAtFormat)) ?? base.secondaryResetAtFormat
        orgIdURL = try? c.decode(String.self, forKey: .orgIdURL)
        orgIdPath = try? c.decode(String.self, forKey: .orgIdPath)
        tokenURL = try? c.decode(String.self, forKey: .tokenURL)
        tokenPath = try? c.decode(String.self, forKey: .tokenPath)
        tokenHeaderName = try? c.decode(String.self, forKey: .tokenHeaderName)
        tokenHeaderPrefix = (try? c.decode(String.self, forKey: .tokenHeaderPrefix)) ?? base.tokenHeaderPrefix
        useHiddenBrowser = (try? c.decode(Bool.self, forKey: .useHiddenBrowser)) ?? base.useHiddenBrowser
    }

    init(name: String, enabled: Bool = true, url: String, method: String = "GET",
         headers: [String: String] = [:], body: String? = nil,
         percentPath: String? = nil, percentIsFraction: Bool = false,
         usedPath: String? = nil, limitPath: String? = nil,
         resetAtPath: String? = nil, resetAtFormat: String = "auto",
         primaryLabel: String = "primary", shortName: String? = nil,
         secondaryLabel: String? = nil, secondaryPercentPath: String? = nil,
         secondaryPercentIsFraction: Bool = false, secondaryResetAtPath: String? = nil,
         secondaryResetAtFormat: String = "auto",
         orgIdURL: String? = nil, orgIdPath: String? = nil,
         tokenURL: String? = nil, tokenPath: String? = nil,
         tokenHeaderName: String? = nil, tokenHeaderPrefix: String = "",
         useHiddenBrowser: Bool = false) {
        self.name = name
        self.enabled = enabled
        self.url = url
        self.method = method
        self.headers = headers
        self.body = body
        self.percentPath = percentPath
        self.percentIsFraction = percentIsFraction
        self.usedPath = usedPath
        self.limitPath = limitPath
        self.resetAtPath = resetAtPath
        self.resetAtFormat = resetAtFormat
        self.primaryLabel = primaryLabel
        self.shortName = shortName
        self.secondaryLabel = secondaryLabel
        self.secondaryPercentPath = secondaryPercentPath
        self.secondaryPercentIsFraction = secondaryPercentIsFraction
        self.secondaryResetAtPath = secondaryResetAtPath
        self.secondaryResetAtFormat = secondaryResetAtFormat
        self.orgIdURL = orgIdURL
        self.orgIdPath = orgIdPath
        self.tokenURL = tokenURL
        self.tokenPath = tokenPath
        self.tokenHeaderName = tokenHeaderName
        self.tokenHeaderPrefix = tokenHeaderPrefix
        self.useHiddenBrowser = useHiddenBrowser
    }
}

struct AppConfig: Codable {
    var refreshIntervalSeconds: Int = 300
    var providers: [ProviderConfig] = []
    /// Bumped whenever the built-in provider defaults change, so an older config on disk
    /// gets rebuilt from the new template (keeping only which providers were enabled)
    /// instead of silently keeping stale endpoints or JSON paths.
    var configVersion: Int = 0

    init(refreshIntervalSeconds: Int = 300, providers: [ProviderConfig] = [], configVersion: Int = 0) {
        self.refreshIntervalSeconds = refreshIntervalSeconds
        self.providers = providers
        self.configVersion = configVersion
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        refreshIntervalSeconds = (try? c.decode(Int.self, forKey: .refreshIntervalSeconds)) ?? 300
        providers = (try? c.decode([ProviderConfig].self, forKey: .providers)) ?? []
        configVersion = (try? c.decode(Int.self, forKey: .configVersion)) ?? 0
    }
}

enum ConfigStore {
    static let dir: URL = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("UsageOverlay", isDirectory: true)
    }()

    static var configURL: URL { dir.appendingPathComponent("config.json") }
    static var secretsURL: URL { dir.appendingPathComponent("secrets.json") }

    static func ensureDir() {
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    static func load() -> AppConfig {
        substituteSecrets(loadRaw())
    }

    static let currentConfigVersion = 4

    /// Config as stored on disk, with `${secret}` placeholders intact (not substituted).
    static func loadRaw() -> AppConfig {
        ensureDir()
        if let data = try? Data(contentsOf: configURL),
           let cfg = try? JSONDecoder().decode(AppConfig.self, from: data) {
            guard cfg.configVersion != currentConfigVersion else { return cfg }
            let migrated = migrate(cfg)
            save(migrated)
            return migrated
        }
        let template = defaultTemplate()
        save(template)
        writeSecretsTemplateIfMissing()
        return template
    }

    /// Rebuilds providers from the current template, carrying over each provider's
    /// `enabled` flag so a user who already logged in stays connected.
    private static func migrate(_ old: AppConfig) -> AppConfig {
        var fresh = defaultTemplate()
        fresh.refreshIntervalSeconds = old.refreshIntervalSeconds
        for i in fresh.providers.indices {
            if let previous = old.providers.first(where: { $0.name == fresh.providers[i].name }) {
                fresh.providers[i].enabled = previous.enabled
            }
        }
        return fresh
    }

    /// Stores `value` under `key` in secrets.json (creating it if needed).
    static func setSecret(_ key: String, _ value: String) {
        ensureDir()
        var dict = loadSecrets()
        dict[key] = value
        if let data = try? JSONEncoder().encode(dict) {
            try? data.write(to: secretsURL)
            try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: secretsURL.path)
        }
    }

    static func setProviderEnabled(name: String, enabled: Bool) {
        var cfg = loadRaw()
        if let idx = cfg.providers.firstIndex(where: { $0.name == name }) {
            cfg.providers[idx].enabled = enabled
            save(cfg)
        }
    }

    static func isProviderEnabled(name: String) -> Bool {
        loadRaw().providers.first(where: { $0.name == name })?.enabled ?? false
    }

    static func save(_ config: AppConfig) {
        ensureDir()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let data = try? encoder.encode(config) {
            try? data.write(to: configURL)
        }
    }

    private static func loadSecrets() -> [String: String] {
        guard let data = try? Data(contentsOf: secretsURL),
              let dict = try? JSONDecoder().decode([String: String].self, from: data) else {
            return [:]
        }
        return dict
    }

    private static func writeSecretsTemplateIfMissing() {
        guard !FileManager.default.fileExists(atPath: secretsURL.path) else { return }
        let template: [String: String] = [
            "claude_cookie": "PASTE_FULL_claude.ai_COOKIE_HEADER_HERE_e.g._sessionKey=...; lastActiveOrg=...",
            "chatgpt_cookie": "PASTE_FULL_chatgpt.com_COOKIE_HEADER_HERE_e.g._name1=value1; name2=value2"
        ]
        if let data = try? JSONEncoder().encode(template) {
            try? data.write(to: secretsURL)
            try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: secretsURL.path)
        }
    }

    /// Replaces "${key}" occurrences in header values with secrets.json values.
    private static func substituteSecrets(_ config: AppConfig) -> AppConfig {
        let secrets = loadSecrets()
        var cfg = config
        for i in cfg.providers.indices {
            for (k, v) in cfg.providers[i].headers {
                var newValue = v
                for (sk, sv) in secrets {
                    newValue = newValue.replacingOccurrences(of: "${\(sk)}", with: sv)
                }
                cfg.providers[i].headers[k] = newValue
            }
        }
        return cfg
    }

    private static func defaultTemplate() -> AppConfig {
        // Endpoint shape confirmed against github.com/SlavomirDurej/claude-usage-widget:
        // GET https://claude.ai/api/organizations -> [{ "uuid": "...", ... }, ...]
        // GET https://claude.ai/api/organizations/{organizationId}/usage
        //   -> { "five_hour": {"utilization": 0-100, "resets_at": iso8601},
        //        "seven_day":  {"utilization": 0-100, "resets_at": iso8601}, ... }
        // Auth: Cookie header "sessionKey=<value copied from claude.ai>".
        // Just paste your sessionKey into secrets.json and flip enabled to true.
        let claude = ProviderConfig(
            name: "Claude",
            enabled: false,
            url: "https://claude.ai/api/organizations/{organizationId}/usage",
            method: "GET",
            headers: [
                "Cookie": "${claude_cookie}",
                "Accept": "application/json, text/plain, */*",
                "Accept-Language": "en-US,en;q=0.9",
                "Referer": "https://claude.ai/settings/usage",
                "Origin": "https://claude.ai",
                "User-Agent": "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.4 Safari/605.1.15"
            ],
            percentPath: "five_hour.utilization",
            percentIsFraction: false,
            resetAtPath: "five_hour.resets_at",
            resetAtFormat: "auto",
            primaryLabel: "5시간",
            shortName: "CL",
            secondaryLabel: "주간",
            secondaryPercentPath: "seven_day.utilization",
            secondaryPercentIsFraction: false,
            secondaryResetAtPath: "seven_day.resets_at",
            secondaryResetAtFormat: "auto",
            orgIdURL: "https://claude.ai/api/organizations",
            orgIdPath: "[0].uuid",
            useHiddenBrowser: true
        )
        // Verified against a live response (see last-response-ChatGPT.json):
        // Step 1: GET https://chatgpt.com/api/auth/session (with chatgpt.com session cookies)
        //         -> { "accessToken": "...", ... }
        // Step 2: GET https://chatgpt.com/backend-api/wham/usage
        //         with header "Authorization: Bearer <accessToken>"
        //         -> { "rate_limit": {
        //                "primary_window":   { "limit_window_seconds": 18000,  <- 5 hours
        //                                      "used_percent": 0-100, "reset_at": <unix seconds> },
        //                "secondary_window": { "limit_window_seconds": 604800, <- 7 days
        //                                      "used_percent": 0-100, "reset_at": <unix seconds> } } }
        // These are the same two windows the official ChatGPT app shows under "남은 사용량"
        // (it prints them as *remaining*, i.e. 100 - used_percent).
        let chatgpt = ProviderConfig(
            name: "ChatGPT",
            enabled: false,
            url: "https://chatgpt.com/backend-api/wham/usage",
            method: "GET",
            headers: ["Cookie": "${chatgpt_cookie}"],
            percentPath: "rate_limit.primary_window.used_percent",
            percentIsFraction: false,
            resetAtPath: "rate_limit.primary_window.reset_at",
            resetAtFormat: "auto",
            primaryLabel: "5시간",
            shortName: "GPT",
            secondaryLabel: "주간",
            secondaryPercentPath: "rate_limit.secondary_window.used_percent",
            secondaryPercentIsFraction: false,
            secondaryResetAtPath: "rate_limit.secondary_window.reset_at",
            secondaryResetAtFormat: "auto",
            tokenURL: "https://chatgpt.com/api/auth/session",
            tokenPath: "accessToken",
            tokenHeaderName: "Authorization",
            tokenHeaderPrefix: "Bearer "
        )
        return AppConfig(refreshIntervalSeconds: 300, providers: [claude, chatgpt],
                         configVersion: currentConfigVersion)
    }
}
