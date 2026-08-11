/// What this install is, as far as the person using it is concerned.
///
/// Two states and no third, because there is no half-signed-in: the identity
/// either carries an Apple credential or it does not, and everything about the
/// app works either way.
public enum AccountState: Sendable, Equatable {
    /// Not bound to any Apple account: the practice is filed under the
    /// anonymous id, reachable from this install and nowhere else. The state a
    /// person is in until they choose otherwise, and a first-class choice
    /// rather than a degraded one — nobody should have to sign in to breathe.
    case localOnly

    /// Bound to an Apple account, so this practice is reachable from a new
    /// phone, a restore, or a second device.
    case signedIn

    /// What Settings shows beside the account row.
    ///
    /// "Not signed in" rather than the "Local only" it used to say, because
    /// local was an overclaim: an anonymous install still has a row, a journey
    /// and possibly a subscription on the server — the deletion says "and from
    /// our servers" in both states for exactly that reason. What this state
    /// truly lacks is the Apple binding, so that is what the row states.
    public var title: String {
        switch self {
        case .localOnly: "Not signed in"
        case .signedIn: "Signed in with Apple"
        }
    }
}
