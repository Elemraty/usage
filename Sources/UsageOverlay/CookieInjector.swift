import Cocoa
import WebKit

/// Writes a cookie straight into the shared persistent cookie jar that both the login
/// window and HiddenWebFetcher use.
///
/// This is the escape hatch for accounts that sign in with Google: Google refuses OAuth
/// inside embedded web views (an anti-phishing policy), so those users can't complete the
/// in-app login. Instead they log in with their normal browser and paste the one cookie
/// that proves the session — no need to work around Google's check at all.
enum CookieInjector {
    static func set(name: String, value: String, domain: String, completion: @escaping (Bool) -> Void) {
        DispatchQueue.main.async {
            guard let cookie = HTTPCookie(properties: [
                .name: name,
                .value: value,
                .domain: domain,
                .path: "/",
                .secure: "TRUE",
                .expires: Date().addingTimeInterval(60 * 60 * 24 * 365)
            ]) else {
                completion(false)
                return
            }
            WKWebsiteDataStore.default().httpCookieStore.setCookie(cookie) {
                completion(true)
            }
        }
    }
}
