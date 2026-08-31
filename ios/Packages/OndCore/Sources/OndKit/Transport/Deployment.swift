/// Where the deployed backend lives. In the package because both targets
/// must reach the same box and nothing reconciles two copies of a hostname.
/// `AppConfiguration` and `WatchConfiguration` resolve it through different
/// chains — the phone honours an environment override the wrist does not —
/// but the answer they fall back to is one fact, so it is stored once.
public enum Deployment {
    /// The deployed API's base URL. A subdomain, so the record behind the name
    /// can move without an App Store release. This is the copy of the hostname
    /// nothing can derive: the Caddyfile renders from `infra/main.tf`'s `api`
    /// record, which a compiled binary cannot read — changing that record
    /// without changing this ships an app pointing at a dead name.
    public static let apiBaseURL = "https://api.ondbreathe.app"
}
