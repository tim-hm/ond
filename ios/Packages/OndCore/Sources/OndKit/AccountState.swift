/// What this install is, as far as the person using it is concerned.
///
/// Two states and no third, because there is no half-signed-in: the identity
/// either carries an Apple credential or it does not, and everything about the
/// app works either way.
public enum AccountState: Sendable, Equatable {
    /// Everything on this device and nothing filed anywhere under a name. The
    /// state a person is in until they choose otherwise, and a first-class
    /// choice rather than a degraded one — nobody should have to sign in to
    /// breathe.
    case localOnly

    /// Bound to an Apple account, so this practice is reachable from a new
    /// phone, a restore, or a second device.
    case signedIn

    /// What Settings shows beside the account row.
    public var title: String {
        switch self {
        case .localOnly: "Local only"
        case .signedIn: "Signed in with Apple"
        }
    }
}
