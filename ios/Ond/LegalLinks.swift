import Foundation

/// The two documents a subscription app has to be able to show. App-local
/// rather than in `Features/Plus/`: App Review expects both reachable from
/// Settings too. Both trap on an unparseable literal, as
/// `AppConfiguration.apiBaseURL` does — a `Link` that quietly opens the wrong
/// page is harder to notice than a crash, and a reviewer will tap these two.
enum LegalLinks {
    /// Apple's standard EULA, which is the terms this app ships under. Using
    /// Apple's own document rather than writing one is what makes this a link to
    /// a page that already exists and is already agreed.
    static let termsOfUse = url("https://www.apple.com/legal/internet-services/itunes/dev/stdeula/")

    /// Served from `web/privacy.html` on the apex — the API's subdomain does
    /// not serve the page. The extensionless form resolves only because
    /// `infra/box/Caddyfile.tmpl` has a `try_files` naming this literal;
    /// App Review rejects a paywall whose privacy link 404s.
    static let privacyPolicy = url("https://ondbreathe.app/privacy")

    private static func url(_ raw: String) -> URL {
        guard let url = URL(string: raw) else {
            preconditionFailure("not a valid URL: \(raw)")
        }

        return url
    }
}
