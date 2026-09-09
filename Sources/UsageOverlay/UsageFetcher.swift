import Foundation

struct UsageWindow {
    var label: String
    var percent: Double?   // 0-100
    var resetsAt: Date?
}

struct ProviderResult {
    var name: String
    var primary: UsageWindow
    var secondary: UsageWindow?
    var error: String?
}

struct SimpleError: Error {
    let message: String
}

/// Saves the last successful response next to the config, so an unknown field name can be
/// looked up without attaching a debugger or opening browser devtools.
func dumpLastResponse(_ json: Any, provider: String) {
    guard let data = try? JSONSerialization.data(withJSONObject: json,
                                                  options: [.prettyPrinted, .sortedKeys]) else { return }
    let url = ConfigStore.dir.appendingPathComponent("last-response-\(provider).json")
    try? data.write(to: url)
}

/// Short preview of a parsed JSON value for error messages (helps diagnose a wrong
/// percentPath/orgIdPath without needing to open devtools).
func jsonSnippet(_ json: Any, maxLength: Int = 160) -> String {
    guard let data = try? JSONSerialization.data(withJSONObject: json, options: [.sortedKeys]),
          let s = String(data: data, encoding: .utf8) else {
        return "(unprintable)"
    }
    return s.count > maxLength ? String(s.prefix(maxLength)) + "…" : s
}

enum UsageFetcher {
    // Cached per provider name for the process lifetime (org ids / tokens don't change often).
    private static var orgIdCache: [String: String] = [:]
    private static var tokenCache: [String: String] = [:]

    static func fetch(_ provider: ProviderConfig, completion: @escaping (ProviderResult) -> Void) {
        guard provider.enabled, provider.url.hasPrefix("http") else {
            completion(ProviderResult(name: provider.name,
                                       primary: UsageWindow(label: "primary", percent: nil, resetsAt: nil),
                                       secondary: nil,
                                       error: "not configured"))
            return
        }

        resolveToken(provider) { tokenResult in
            switch tokenResult {
            case .failure(let err):
                completion(ProviderResult(name: provider.name,
                                           primary: UsageWindow(label: "primary", percent: nil, resetsAt: nil),
                                           secondary: nil,
                                           error: err.message))
            case .success(let withToken):
                if withToken.url.contains("{organizationId}") {
                    resolveOrgId(withToken) { result in
                        switch result {
                        case .success(let orgId):
                            var resolved = withToken
                            resolved.url = withToken.url.replacingOccurrences(of: "{organizationId}", with: orgId)
                            performFetch(resolved, completion: completion)
                        case .failure(let err):
                            completion(ProviderResult(name: provider.name,
                                                       primary: UsageWindow(label: "primary", percent: nil, resetsAt: nil),
                                                       secondary: nil,
                                                       error: err.message))
                        }
                    }
                } else {
                    performFetch(withToken, completion: completion)
                }
            }
        }
    }

    /// If `tokenURL`/`tokenPath` are configured, fetches (or reuses the cached) token
    /// and returns a copy of `provider` with `tokenHeaderName` set.
    private static func resolveToken(_ provider: ProviderConfig, completion: @escaping (Result<ProviderConfig, SimpleError>) -> Void) {
        guard let tokenURLString = provider.tokenURL, let tokenPath = provider.tokenPath,
              let tokenHeaderName = provider.tokenHeaderName,
              let tokenURL = URL(string: tokenURLString) else {
            completion(.success(provider))
            return
        }
        if let cached = tokenCache[provider.name] {
            var withToken = provider
            withToken.headers[tokenHeaderName] = provider.tokenHeaderPrefix + cached
            completion(.success(withToken))
            return
        }
        var request = URLRequest(url: tokenURL)
        for (k, v) in provider.headers { request.setValue(v, forHTTPHeaderField: k) }
        let task = URLSession.shared.dataTask(with: request) { data, response, error in
            if let error = error {
                completion(.failure(SimpleError(message: error.localizedDescription)))
                return
            }
            guard let data = data,
                  let http = response as? HTTPURLResponse,
                  (200..<300).contains(http.statusCode) else {
                let code = (response as? HTTPURLResponse)?.statusCode ?? -1
                completion(.failure(SimpleError(message: "token lookup HTTP \(code)")))
                return
            }
            guard let json = try? JSONSerialization.jsonObject(with: data),
                  let token = JSONPath.string(in: json, path: tokenPath) else {
                completion(.failure(SimpleError(message: "could not read tokenPath from token lookup response")))
                return
            }
            tokenCache[provider.name] = token
            var withToken = provider
            withToken.headers[tokenHeaderName] = provider.tokenHeaderPrefix + token
            completion(.success(withToken))
        }
        task.resume()
    }

    /// Fetches `url` as JSON, either via a plain HTTPS request (with `provider.headers`)
    /// or, when `provider.useHiddenBrowser` is set, via a real WKWebView so sites behind
    /// a Cloudflare bot challenge see a real browser instead of a bare HTTP client.
    private static func fetchJSON(_ provider: ProviderConfig, url: URL, completion: @escaping (Result<Any, SimpleError>) -> Void) {
        if provider.useHiddenBrowser {
            HiddenWebFetcher.fetchJSON(url: url, completion: completion)
            return
        }
        var request = URLRequest(url: url)
        request.httpMethod = provider.method
        for (k, v) in provider.headers { request.setValue(v, forHTTPHeaderField: k) }
        if let body = provider.body { request.httpBody = body.data(using: .utf8) }
        let task = URLSession.shared.dataTask(with: request) { data, response, error in
            if let error = error {
                completion(.failure(SimpleError(message: error.localizedDescription)))
                return
            }
            guard let data = data,
                  let http = response as? HTTPURLResponse,
                  (200..<300).contains(http.statusCode) else {
                let code = (response as? HTTPURLResponse)?.statusCode ?? -1
                completion(.failure(SimpleError(message: "HTTP \(code)")))
                return
            }
            guard let json = try? JSONSerialization.jsonObject(with: data) else {
                completion(.failure(SimpleError(message: "bad JSON")))
                return
            }
            completion(.success(json))
        }
        task.resume()
    }

    private static func resolveOrgId(_ provider: ProviderConfig, completion: @escaping (Result<String, SimpleError>) -> Void) {
        if let cached = orgIdCache[provider.name] {
            completion(.success(cached))
            return
        }
        guard let orgIdURLString = provider.orgIdURL, let orgIdPath = provider.orgIdPath,
              let orgIdURL = URL(string: orgIdURLString) else {
            completion(.failure(SimpleError(message: "orgIdURL/orgIdPath not configured")))
            return
        }
        fetchJSON(provider, url: orgIdURL) { result in
            switch result {
            case .failure(let err):
                completion(.failure(SimpleError(message: "org lookup: \(err.message)")))
            case .success(let json):
                guard let orgId = JSONPath.string(in: json, path: orgIdPath) else {
                    let snippet = jsonSnippet(json)
                    completion(.failure(SimpleError(message: "org lookup: unexpected response \(snippet)")))
                    return
                }
                orgIdCache[provider.name] = orgId
                completion(.success(orgId))
            }
        }
    }

    private static func performFetch(_ provider: ProviderConfig, completion: @escaping (ProviderResult) -> Void) {
        guard let url = URL(string: provider.url) else {
            completion(ProviderResult(name: provider.name,
                                       primary: UsageWindow(label: "primary", percent: nil, resetsAt: nil),
                                       secondary: nil,
                                       error: "bad URL"))
            return
        }

        fetchJSON(provider, url: url) { result in
            switch result {
            case .failure(let err):
                completion(ProviderResult(name: provider.name,
                                           primary: UsageWindow(label: "primary", percent: nil, resetsAt: nil),
                                           secondary: nil,
                                           error: err.message))
            case .success(let json):
                dumpLastResponse(json, provider: provider.name)
                let primary = extractWindow(
                    json: json, label: provider.primaryLabel,
                    percentPath: provider.percentPath, percentIsFraction: provider.percentIsFraction,
                    usedPath: provider.usedPath, limitPath: provider.limitPath,
                    resetAtPath: provider.resetAtPath, resetAtFormat: provider.resetAtFormat
                )
                var secondary: UsageWindow? = nil
                if let secLabel = provider.secondaryLabel {
                    secondary = extractWindow(
                        json: json, label: secLabel,
                        percentPath: provider.secondaryPercentPath, percentIsFraction: provider.secondaryPercentIsFraction,
                        usedPath: nil, limitPath: nil,
                        resetAtPath: provider.secondaryResetAtPath, resetAtFormat: provider.secondaryResetAtFormat
                    )
                }
                let diagnosticError = primary.percent == nil ? "couldn't read percentPath, got \(jsonSnippet(json))" : nil
                completion(ProviderResult(name: provider.name, primary: primary, secondary: secondary, error: diagnosticError))
            }
        }
    }

    private static func extractWindow(json: Any, label: String,
                                       percentPath: String?, percentIsFraction: Bool,
                                       usedPath: String?, limitPath: String?,
                                       resetAtPath: String?, resetAtFormat: String) -> UsageWindow {
        var percent: Double? = nil
        if let pp = percentPath, let v = JSONPath.double(in: json, path: pp) {
            percent = percentIsFraction ? v * 100 : v
        } else if let up = usedPath, let lp = limitPath,
                  let used = JSONPath.double(in: json, path: up),
                  let limit = JSONPath.double(in: json, path: lp), limit > 0 {
            percent = used / limit * 100
        }

        var resetsAt: Date? = nil
        if let rp = resetAtPath {
            resetsAt = parseResetDate(json: json, path: rp, format: resetAtFormat)
        }

        return UsageWindow(label: label, percent: percent, resetsAt: resetsAt)
    }

    private static func parseResetDate(json: Any, path: String, format: String) -> Date? {
        guard let raw = JSONPath.value(in: json, path: path) else { return nil }

        func asEpochSeconds(_ n: Double) -> Date { Date(timeIntervalSince1970: n) }
        func asEpochMillis(_ n: Double) -> Date { Date(timeIntervalSince1970: n / 1000) }
        func asISO8601(_ s: String) -> Date? {
            if let d = ISO8601DateFormatter().date(from: s) { return d }
            let withFractional = ISO8601DateFormatter()
            withFractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            return withFractional.date(from: s)
        }

        switch format {
        case "epochSeconds":
            if let n = raw as? NSNumber { return asEpochSeconds(n.doubleValue) }
        case "epochMillis":
            if let n = raw as? NSNumber { return asEpochMillis(n.doubleValue) }
        case "iso8601":
            if let s = raw as? String { return asISO8601(s) }
        default:
            break // "auto" falls through below
        }

        // auto-detect: numbers are epoch (seconds vs millis by magnitude), strings are ISO8601.
        if let n = raw as? NSNumber {
            let v = n.doubleValue
            // ~13 digits (>= year 2001 in ms) vs ~10 digits (seconds): use 10^12 as the cutover.
            return v > 1_000_000_000_000 ? asEpochMillis(v) : asEpochSeconds(v)
        }
        if let s = raw as? String {
            if let d = asISO8601(s) { return d }
            if let n = Double(s) {
                return n > 1_000_000_000_000 ? asEpochMillis(n) : asEpochSeconds(n)
            }
        }
        return nil
    }
}
