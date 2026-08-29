import Foundation

extension [String: Any] {
    /// A UUID stored as its string form — the payloads are property lists,
    /// and `UUID` is not a property-list type.
    func uuid(_ key: String) -> UUID? {
        (self[key] as? String).flatMap(UUID.init(uuidString:))
    }
}

/// One thing the phone asks the wrist to do, and when it asked. It rides in
/// `WatchHandoff`'s context rather than as a message: `startWatchApp` carries
/// no payload, and a message sent while the watch app is launching is lost —
/// state survives. Replay is made safe by `id`, which `WatchOrderLedger`
/// runs at most once, and `issuedAt`, which lets an undelivered order expire.
public struct WatchSessionOrder: Sendable, Equatable {
    /// What the wrist is being asked for. Two errands share one channel
    /// because they share the whole mechanism; an enum is what stops a
    /// reading errand carrying slugs, or a breathing one arriving without
    /// them.
    public enum Errand: Sendable, Equatable {
        /// Run this occasion's session here, tapped out rather than shown.
        ///
        /// The technique comes resolved: the wrist runs what the tapped card
        /// named, not what its own copy of the routes happens to send this
        /// occasion to.
        case breathe(occasionSlug: String, techniqueSlug: String)
        /// Wear the sensor for a session running on the phone.
        ///
        /// No cadence, no record, nothing written to Health — the phone owns
        /// that session entirely, and the wrist only reports what it can feel.
        /// Nothing to name, so nothing is carried.
        case sharePulse
    }

    /// Names this order for its whole life: the ledger entry that stops a
    /// replay, the ack the phone's timeout waits on, the readings shared under
    /// it, and the completion notice that closes the loop.
    public let id: UUID
    public let errand: Errand
    /// When the phone issued it, for `WatchOrderLedger`'s freshness window.
    public let issuedAt: Date

    public init(id: UUID, errand: Errand, issuedAt: Date) {
        self.id = id
        self.errand = errand
        self.issuedAt = issuedAt
    }

    private static let idKey = "id"
    private static let kindKey = "kind"
    private static let occasionKey = "occasionSlug"
    private static let techniqueKey = "techniqueSlug"
    private static let issuedAtKey = "issuedAt"

    /// The errand's name on the wire. Spelled out rather than derived from the
    /// case, because a context is a stored format the other device decodes: a
    /// case renamed on one side must not change what the other reads.
    private static let breatheKind = "breathe"
    private static let sharePulseKind = "sharePulse"

    /// The property-list shape `WatchHandoff` nests under its order key. `Date`
    /// travels as itself — it is a plist type, and both ends speak it.
    public var dictionary: [String: Any] {
        var order: [String: Any] = [Self.idKey: id.uuidString, Self.issuedAtKey: issuedAt]
        switch errand {
        case let .breathe(occasionSlug, techniqueSlug):
            order[Self.kindKey] = Self.breatheKind
            order[Self.occasionKey] = occasionSlug
            order[Self.techniqueKey] = techniqueSlug

        case .sharePulse:
            order[Self.kindKey] = Self.sharePulseKind
        }
        return order
    }

    /// Reads an order out of a context, or nil where any field is missing or
    /// unreadable — a half-order is not one the wrist can run, and there is
    /// nothing to do about a malformed one but ignore it.
    public init?(dictionary: [String: Any]) {
        guard let id = dictionary.uuid(Self.idKey),
              let issuedAt = dictionary[Self.issuedAtKey] as? Date,
              let errand = Self.errand(from: dictionary)
        else {
            return nil
        }

        self.init(id: id, errand: errand, issuedAt: issuedAt)
    }

    /// The errand, or nil for one this build does not know — an older watch
    /// reading a newer phone's context. Nil rather than a default: the wrist
    /// would otherwise answer an errand it cannot perform, and the phone would
    /// spend its whole window waiting for the wrong thing to happen.
    private static func errand(from dictionary: [String: Any]) -> Errand? {
        switch dictionary[kindKey] as? String {
        case breatheKind:
            guard let occasionSlug = dictionary[occasionKey] as? String,
                  let techniqueSlug = dictionary[techniqueKey] as? String
            else {
                return nil
            }
            return .breathe(occasionSlug: occasionSlug, techniqueSlug: techniqueSlug)

        case sharePulseKind:
            return .sharePulse

        default:
            return nil
        }
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

/// The wrist saying an ordered session has ended and kept a record: the
/// phone's cue to fetch history again. Queued (`transferUserInfo`) rather
/// than live, deliberately — the session can end half an hour later, and the
/// notice still means what it meant. Only the order's id travels: the phone
/// fetches the newest page whatever this names; extra fields only risk decode.
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
