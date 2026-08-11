import Foundation

/// One heart-rate reading, on its way from the wrist to a session running on the
/// phone.
///
/// A live message rather than state, and the only payload in the pairing that is
/// sent over and over. It is worth nothing a moment later — a badge showing a
/// rate from two minutes ago is worse than a badge showing none — so a reading
/// that cannot be delivered is dropped where it stands and the next one goes
/// instead.
///
/// No timestamp travels with it. The phone times the arrival itself, on its own
/// clock, because what it needs to know is "has anything reached me lately" and
/// two devices' `Date`s answer a slightly different question. A field nobody
/// reads is one more thing a decode can fail on.
public struct WatchPulse: Sendable, Equatable {
    /// The order this is being shared under. Carried so a phone whose session
    /// has ended and begun again does not draw the first session's readings —
    /// the wrist may still be finishing with the order it was given.
    public let orderId: UUID
    /// Whole beats per minute. Rounded on the wrist, because whole beats are
    /// what the badge shows and a fraction would only make two readings that
    /// display identically compare unequal.
    public let beatsPerMinute: Int

    public init(orderId: UUID, beatsPerMinute: Int) {
        self.orderId = orderId
        self.beatsPerMinute = beatsPerMinute
    }

    /// Deliberately not the ack's or the notice's key. The three payloads travel
    /// through one decoder each, and distinct keys mean none can be read as
    /// another.
    private static let orderKey = "pulseOrderId"
    private static let rateKey = "beatsPerMinute"

    public var dictionary: [String: Any] {
        [Self.orderKey: orderId.uuidString, Self.rateKey: beatsPerMinute]
    }

    public init?(dictionary: [String: Any]) {
        guard let orderId = dictionary.uuid(Self.orderKey),
              let beatsPerMinute = dictionary[Self.rateKey] as? Int
        else {
            return nil
        }

        self.init(orderId: orderId, beatsPerMinute: beatsPerMinute)
    }
}

/// The phone's answer to a reading: whether it still wants them.
///
/// Every reading carries its own reply, and that is what makes the arrangement
/// end cleanly from either side. The wrist cannot see a phone session finish, and
/// the phone cannot count on being able to reach a wrist to say so — but a wrist
/// that is still sending has by definition just reached the phone, so the reply
/// is the one moment the news is guaranteed to travel.
///
/// It covers the cases a "stop" message cannot. A phone app that was killed and
/// relaunched in the background to take this very message has no session and no
/// arrangement, so it answers no and the wrist puts the sensor down — where a
/// stop it never got the chance to send would have left a workout running on
/// somebody's wrist until they noticed.
public struct WatchPulseReply: Sendable, Equatable {
    /// Whether to keep them coming. False for a phone with no session, a
    /// session that has ended, and a reading shared under a spent order.
    public let isWanted: Bool

    public init(isWanted: Bool) {
        self.isWanted = isWanted
    }

    private static let wantedKey = "wantsPulse"

    public var dictionary: [String: Any] {
        [Self.wantedKey: isWanted]
    }

    /// An unreadable reply is no, on the reasoning every silence in this file
    /// gets: the wrist holding a workout open is the expensive mistake, and
    /// stopping costs a person a badge they can bring back by starting again.
    public init?(dictionary: [String: Any]) {
        guard let isWanted = dictionary[Self.wantedKey] as? Bool else { return nil }
        self.init(isWanted: isWanted)
    }
}
