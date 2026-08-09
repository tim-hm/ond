import OndKit

/// The one identity store this app reads, shared rather than rebuilt.
///
/// `KeychainUserIdentityStore` remembers the id it resolved for the life of the
/// process, so a second instance is a second cache. That is harmless right up
/// until a sign-in merges this install into an older identity: the instance
/// nobody told goes on stamping the id the server has just deleted onto every
/// request it makes, the server recreates that row empty, and those writes land
/// on an orphan no Apple account points at.
///
/// A static rather than a property initialised in `OndApp`, even though the
/// composition root is its only reader, because "one instance" here has to be
/// a property of the process and not of how many times SwiftUI builds the
/// `App` value — the cache above is only safe while nothing can ever mint a
/// second copy.
enum LiveIdentity {
    static let store = KeychainUserIdentityStore()
}
