import Foundation

extension [String: Any] {
    /// A UUID stored as its string form, which is the only shape `WCSession`
    /// will carry one in — the payloads are property lists, and `UUID` is not a
    /// property-list type.
    ///
    /// Here because four codecs across the pairing read one, and each hand-
    /// rolled the same throwaway binding and pair of guards.
    func uuid(_ key: String) -> UUID? {
        (self[key] as? String).flatMap(UUID.init(uuidString:))
    }
}

/// One session the phone asks the wrist to run: which occasion, which
/// technique, and when it was asked.
///
/// It rides inside `WatchHandoff`'s applicationContext dictionary rather than
/// travelling as a message, because the launch call itself carries no payload —
/// `startWatchApp` wakes the watch app and says nothing — and a message sent
/// while the watch app is still launching is a message lost. State survives
/// that: the system delivers the last context whenever the watch next runs.
///
/// What makes an order safe to encode as state the system replays on every
/// activation is the pair of fields that are not the session: `id`, which
/// `WatchOrderLedger` runs at most once, and `issuedAt`, which lets an order
/// nobody delivered expire rather than buzz a wrist at midnight.
public struct WatchSessionOrder: Sendable, Equatable {
    /// Names this order for its whole life: the ledger entry that stops a
    /// replay, the ack the phone's timeout waits on, and the completion notice
    /// that closes the loop.
    public let id: UUID
    /// The occasion whose promise the wrist is being asked to keep, stamped
    /// onto the session's record exactly as a wrist-chosen moment would be.
    public let occasionSlug: String
    /// The technique that occasion prescribes, resolved on the phone — the
    /// wrist runs what the tapped card named, not what its own catalogue copy
    /// happens to say this occasion routes to.
    public let techniqueSlug: String
    /// When the phone issued it, for `WatchOrderLedger`'s freshness window.
    public let issuedAt: Date

    public init(id: UUID, occasionSlug: String, techniqueSlug: String, issuedAt: Date) {
        self.id = id
        self.occasionSlug = occasionSlug
        self.techniqueSlug = techniqueSlug
        self.issuedAt = issuedAt
    }

    private static let idKey = "id"
    private static let occasionKey = "occasionSlug"
    private static let techniqueKey = "techniqueSlug"
    private static let issuedAtKey = "issuedAt"

    /// The property-list shape `WatchHandoff` nests under its order key. `Date`
    /// travels as itself — it is a plist type, and both ends speak it.
    public var dictionary: [String: Any] {
        [
            Self.idKey: id.uuidString,
            Self.occasionKey: occasionSlug,
            Self.techniqueKey: techniqueSlug,
            Self.issuedAtKey: issuedAt,
        ]
    }

    /// Reads an order out of a context, or nil where any field is missing or
    /// unreadable — a half-order is not one the wrist can run, and there is
    /// nothing to do about a malformed one but ignore it.
    public init?(dictionary: [String: Any]) {
        guard let id = dictionary.uuid(Self.idKey),
              let occasionSlug = dictionary[Self.occasionKey] as? String,
              let techniqueSlug = dictionary[Self.techniqueKey] as? String,
              let issuedAt = dictionary[Self.issuedAtKey] as? Date
        else {
            return nil
        }

        self.init(
            id: id,
            occasionSlug: occasionSlug,
            techniqueSlug: techniqueSlug,
            issuedAt: issuedAt
        )
    }
}

/// The wrist's answer to an order: taken up, or declined.
///
/// Sent as a live message rather than state, because it is one — the phone's
/// sheet is waiting on it right now, and an ack that arrives tomorrow answers
/// nothing. A lost ack costs exactly the timeout's fallback copy.
public struct WatchOrderAck: Sendable, Equatable {
    public let orderId: UUID
    /// False when the wrist could not honour the order — most plausibly a
    /// catalogue that cannot resolve the ordered technique. The phone shows the
    /// same fallback either way; the field exists so it can stop waiting early.
    public let accepted: Bool

    public init(orderId: UUID, accepted: Bool) {
        self.orderId = orderId
        self.accepted = accepted
    }

    private static let orderKey = "orderId"
    private static let acceptedKey = "accepted"

    public var dictionary: [String: Any] {
        [Self.orderKey: orderId.uuidString, Self.acceptedKey: accepted]
    }

    public init?(dictionary: [String: Any]) {
        guard let orderId = dictionary.uuid(Self.orderKey),
              let accepted = dictionary[Self.acceptedKey] as? Bool
        else {
            return nil
        }

        self.init(orderId: orderId, accepted: accepted)
    }
}

/// The wrist saying an ordered session has ended and kept a record: the phone's
/// cue to ask the server for history again.
///
/// Queued (`transferUserInfo`) rather than live, deliberately — the session ends
/// up to half an hour after the phone stopped watching, and a notice that waits
/// out a pocket or another room still means exactly what it meant.
///
/// The order's id and nothing else. The session's own id would be a field
/// nobody reads: the record travels through the server, so the phone's answer
/// is to fetch, and it fetches the newest page whatever this names. A field
/// carried anyway is one more thing a decode can fail on, and a failed decode
/// here means the phone never looks.
public struct WatchSessionNotice: Sendable, Equatable {
    public let orderId: UUID

    public init(orderId: UUID) {
        self.orderId = orderId
    }

    /// Deliberately not the ack's `orderId`: the two payloads travel different
    /// channels but through one decoder each, and distinct keys mean neither can
    /// ever be read as the other.
    private static let orderKey = "finishedOrderId"

    public var dictionary: [String: Any] {
        [Self.orderKey: orderId.uuidString]
    }

    public init?(dictionary: [String: Any]) {
        guard let orderId = dictionary.uuid(Self.orderKey) else { return nil }
        self.init(orderId: orderId)
    }
}
