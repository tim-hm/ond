import Foundation

/// What the phone tells the wrist about the person using it.
///
/// Carried in WatchConnectivity's `applicationContext`, which is a last-value-
/// wins dictionary the system delivers whenever the watch next runs — exactly
/// the semantics this payload wants, since none of it is an event and a missed
/// update is superseded rather than lost.
///
/// It lives in `OndKit` because both apps have to agree on the key names
/// down to the character, and an agreement written twice is one that drifts. The
/// dictionary is `[String: Any]` because that is what `WCSession` takes; the
/// conversion is confined here so no view or delegate elsewhere handles untyped
/// values.
///
/// Every field is state the wrist cannot derive, and `erasesPriorHistory` is the
/// one that says what the state *means* rather than what it is — see its note.
public struct WatchHandoff: Sendable, Equatable {
    /// The anonymous id both devices attribute their sessions to. The watch
    /// never invents one, so this is the only way it ever gets an identity.
    public let userId: UUID
    /// What proves that id, once the phone has signed in with Apple, and nil
    /// while it has not.
    ///
    /// The wrist needs it for the same reason the phone does: a bound identity
    /// is refused every request that cannot present the credential, and the
    /// watch makes its own — it syncs what was breathed on it. A phone that has
    /// signed out sends nil, which is what stops the wrist presenting a value
    /// the server has revoked.
    ///
    /// It travels the same channel the id already does, which is the pairing
    /// between one phone and one watch. That is not a new exposure: before this,
    /// the id alone was the whole claim to the account, and it has been going
    /// over this channel since the watch app existed.
    public let sessionCredential: String?
    /// The best controlled pause the phone has recorded, or nil before the
    /// first test. Mirrored rather than folded on the watch: the BOLT test is a
    /// phone screen — a stopwatch you hold your breath against — so the wrist
    /// reports the number and never measures it.
    ///
    /// Never zero. Nobody held their breath for no seconds, and a value free to
    /// arrive as either `nil` or `0` would make two handoffs that mean the same
    /// thing compare unequal.
    public let boltBestSeconds: Int?
    /// Whether the identity above replaced one that was **deleted**, rather than
    /// merged away or signed out of.
    ///
    /// The difference matters only to the wrist, and only once. Every other id
    /// change means "this practice is filed under a different name now", and the
    /// watch's own backlog goes up under the new one. This one means there is no
    /// practice: a person asked to be forgotten, the phone has erased its
    /// stores, and anything still on the wrist would sync itself back into the
    /// fresh account they were given.
    ///
    /// Deliberately not an event. `applicationContext` is last-value-wins and
    /// the system replays it on every activation, so this stays true for as long
    /// as the phone carries this identity — and the wrist acts on it only where
    /// adopting the id actually changed something, which can happen once.
    public let erasesPriorHistory: Bool
    /// The session the phone wants the wrist to run, while one is outstanding.
    ///
    /// An event encoded as state, on `erasesPriorHistory`'s exact precedent:
    /// the launch call carries no payload and the system replays this context
    /// on every activation, so the order travels as the last thing the phone
    /// said and `WatchOrderLedger` is what makes the replay run it only once.
    public let order: WatchSessionOrder?

    /// Normalises the score here, in the one initialiser everything else routes
    /// through, so neither the encoder nor the decoder has to remember to.
    public init(
        userId: UUID,
        sessionCredential: String? = nil,
        boltBestSeconds: Int? = nil,
        erasesPriorHistory: Bool = false,
        order: WatchSessionOrder? = nil
    ) {
        self.userId = userId
        self.sessionCredential = sessionCredential
        self.boltBestSeconds = boltBestSeconds.flatMap { $0 > 0 ? $0 : nil }
        self.erasesPriorHistory = erasesPriorHistory
        self.order = order
    }

    private static let userIdKey = "userId"
    private static let credentialKey = "sessionCredential"
    private static let boltBestKey = "boltBestSeconds"
    private static let erasesKey = "erasesPriorHistory"
    private static let orderKey = "order"

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
        return context
    }

    /// Reads a context the phone sent, or nil where it carries no usable id.
    ///
    /// Total and non-throwing: this runs on WatchConnectivity's delivery queue
    /// with whatever the system hands over, including the empty dictionary a
    /// never-configured session reports, and there is nothing a watch app could
    /// do about a malformed one but ignore it.
    public init?(dictionary: [String: Any]) {
        guard let userId = dictionary.uuid(Self.userIdKey) else { return nil }

        // A missing or unreadable flag reads as false, which is the direction
        // that cannot lose anything: the worst it does is leave a wrist holding
        // history the phone has erased, where the opposite would erase a wrist
        // whose phone asked for nothing of the kind. A malformed order reads
        // as none on the same reasoning — the identity it travelled with must
        // still be adopted.
        self.init(
            userId: userId,
            sessionCredential: dictionary[Self.credentialKey] as? String,
            boltBestSeconds: dictionary[Self.boltBestKey] as? Int,
            erasesPriorHistory: dictionary[Self.erasesKey] as? Bool ?? false,
            order: (dictionary[Self.orderKey] as? [String: Any])
                .flatMap(WatchSessionOrder.init(dictionary:))
        )
    }
}
