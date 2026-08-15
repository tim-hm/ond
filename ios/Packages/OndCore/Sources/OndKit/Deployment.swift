/// Where the deployed backend lives.
///
/// In the package rather than in each app's configuration because both targets
/// have to reach the same box and nothing reconciles two copies of a hostname.
/// `AppConfiguration` and `WatchConfiguration` resolve it through deliberately
/// different chains — the phone honours an environment override the wrist does
/// not — but the answer they fall back to is one fact, so it is stored once.
///
/// The failure this prevents is silent in both directions: neither app target
/// has a test bundle, and a wrist left on a stale host would post gRPC-Web at
/// whatever now answers there and read the reply as a protocol error rather
/// than as a wrong address.
public enum Deployment {
    /// The deployed API's base URL.
    ///
    /// A subdomain rather than the apex, and that is the whole point of it: a
    /// shipped build can only ask for the host it was compiled with, so the
    /// record behind this name is the one piece of the address that can move
    /// without an App Store release — and it can only move independently while
    /// the marketing page answers on a different name.
    ///
    /// This is the copy of the hostname that cannot be derived from anything:
    /// the Caddyfile's site block is rendered from the `api` record in
    /// `infra/main.tf`, but a compiled binary has no way to read that record, so
    /// this literal and that resource are reconciled by nobody. Changing the
    /// record without changing this ships an app pointing at a name its own
    /// infrastructure no longer answers on.
    public static let apiBaseURL = "https://api.ondbreathe.app"
}
