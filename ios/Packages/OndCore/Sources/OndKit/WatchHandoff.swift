import Foundation

/// What the phone tells the wrist about the person using it. Carried in
/// WatchConnectivity's `applicationContext` — last-value-wins, delivered
/// whenever the watch next runs — which fits: none of this is an event, and a
/// missed update is superseded rather than lost. In `OndKit` so both apps
/// agree on the key names, and no delegate elsewhere handles untyped values.
public struct WatchHandoff: Sendable, Equatable {
    /// The anonymous id both devices attribute their sessions to. The watch
    /// never invents one, so this is the only way it ever gets an identity.
    public let userId: UUID
    /// What proves that id once the phone has signed in, and nil while it has
    /// not. The wrist syncs what was breathed on it, so a bound identity needs
    /// the credential too; a signed-out phone sends nil, which stops the wrist
    /// presenting a revoked value. It travels the pairing the id always has,
    /// so it is no new exposure.
    public let sessionCredential: String?
    /// The best controlled pause the phone has recorded, or nil before the
    /// first test. The BOLT test is a phone screen, so the wrist reports the
    /// number and never measures it. Never zero: a value free to arrive as
    /// nil or 0 would make two handoffs that mean the same compare unequal.
    public let boltBestSeconds: Int?
    /// Whether the identity above replaced one that was deleted, rather than
    /// merged away or signed out of. Anything still on the wrist would sync
    /// itself back into the fresh account. Deliberately state, not an event:
    /// the system replays this context on every activation, so the wrist acts
    /// on it only where adopting the id actually changed something — once.
    public let erasesPriorHistory: Bool
    /// The session the phone wants the wrist to run, while one is outstanding.
    /// An event encoded as state: the system replays this context on every
    /// activation, so the order travels as the last thing the phone said and
    /// `WatchOrderLedger` makes the replay run it only once.
    public let order: WatchSessionOrder?

    /// The `SafetyConsent.version` this person agreed to on the phone, or nil
    /// while they have not. The wrist asks for itself wherever this does not
    /// cover its own terms, so absent has to mean ask — which is what a context
    /// that never arrived reads as. A version, not a flag, so terms that move
    /// stop being covered by an agreement to the words before them.
    public let agreedConsentVersion: Int?

    /// What the person is entitled to, so the wrist need not ask the App
    /// Store itself. Absent decodes `.free`, the direction that cannot give
    /// anything away. This channel is never itself gated: the tier travels on
    /// it, so a gate in front of the hand-over would be a purchase that could
    /// never reach the wrist.
    public let entitledTier: SubscriptionTier

    /// Normalises the score here, in the one initialiser everything else routes
    /// through, so neither the encoder nor the decoder has to remember to.
    public init(
        userId: UUID,
        sessionCredential: String? = nil,
        boltBestSeconds: Int? = nil,
        erasesPriorHistory: Bool = false,
        order: WatchSessionOrder? = nil,
        agreedConsentVersion: Int? = nil,
        entitledTier: SubscriptionTier = .free
    ) {
        self.userId = userId
        self.sessionCredential = sessionCredential
        self.boltBestSeconds = boltBestSeconds.flatMap { $0 > 0 ? $0 : nil }
        self.erasesPriorHistory = erasesPriorHistory
        self.order = order
        self.agreedConsentVersion = agreedConsentVersion
        self.entitledTier = entitledTier
    }

    private static let userIdKey = "userId"
    private static let credentialKey = "sessionCredential"
    private static let boltBestKey = "boltBestSeconds"
    private static let erasesKey = "erasesPriorHistory"
    private static let orderKey = "order"
    private static let consentKey = "agreedConsentVersion"
    private static let tierKey = "entitledTier"

    public var dictionary: [String: Any] {
        var context: [String: Any] = [Self.userIdKey: userId.uuidString]
        // Absent rather than empty for the majority of people, who never sign
        // in — and absent is what the wrist reads as "clear whatever you hold",
        // which is exactly right after a sign-out.
        if let sessionCredential {
            context[Self.credentialKey] = sessionCredential
        }
        // Absent rather than zero: the key means "there is a best", and the
        // initialiser has already ruled out a zero reaching here.
        if let boltBestSeconds {
            context[Self.boltBestKey] = boltBestSeconds
        }
        // Absent rather than false, so the overwhelming majority of contexts
        // carry exactly the two keys they always have.
        if erasesPriorHistory {
            context[Self.erasesKey] = true
        }
        // Absent while nothing is ordered, which is almost always.
        if let order {
            context[Self.orderKey] = order.dictionary
        }
        if let agreedConsentVersion {
            context[Self.consentKey] = agreedConsentVersion
        }
        // Absent for free, so the majority of contexts carry exactly the keys
        // they always have — and so the decoder's default is the one value a
        // missing key could safely mean.
        if entitledTier > .free {
            context[Self.tierKey] = entitledTier.rawValue
        }
        return context
    }

    /// Reads a context the phone sent, or nil where it carries no usable id.
    /// Total and non-throwing: this runs on WatchConnectivity's delivery
    /// queue with whatever the system hands over, and a watch app can only
    /// ignore a malformed one.
    public init?(dictionary: [String: Any]) {
        guard let userId = dictionary.uuid(Self.userIdKey) else { return nil }

        // A missing or unreadable flag reads as false — the direction that
        // cannot erase a wrist whose phone asked for nothing of the kind. A
        // malformed order reads as none on the same reasoning (the identity
        // it travelled with must still be adopted), and an unknown tier reads
        // as free.
        self.init(
            userId: userId,
            sessionCredential: dictionary[Self.credentialKey] as? String,
            boltBestSeconds: dictionary[Self.boltBestKey] as? Int,
            erasesPriorHistory: dictionary[Self.erasesKey] as? Bool ?? false,
            order: (dictionary[Self.orderKey] as? [String: Any])
                .flatMap(WatchSessionOrder.init(dictionary:)),
            agreedConsentVersion: dictionary[Self.consentKey] as? Int,
            entitledTier: (dictionary[Self.tierKey] as? Int)
                .flatMap(SubscriptionTier.init(rawValue:)) ?? .free
        )
    }
}
