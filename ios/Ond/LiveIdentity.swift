import OndKit

/// The one identity store this app reads. `KeychainUserIdentityStore` caches
/// the id it resolved, so after a sign-in merges this install into an older
/// identity a second instance keeps stamping the deleted id and the server
/// recreates that row as an orphan. A static, not an `OndApp` property:
/// "one instance" must hold per process, not per SwiftUI `App` rebuild.
enum LiveIdentity {
    static let store = KeychainUserIdentityStore()
}
