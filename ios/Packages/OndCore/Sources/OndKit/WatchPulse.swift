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

    /// What a heart rate can be, either side of the radio.
    ///
    /// Wide enough to hold a deep bradycardia at rest and a maximal effort, and
    /// no wider, because this is a decode check rather than a clinical one: what
    /// it has to catch is a number that is not a heart rate at all. Zero is the
    /// one that arrives in practice — the sensor saying it has nothing.
    ///
    /// The wrist reads it as well as the phone, and the asymmetry is the point:
    /// a reading dropped where it is taken costs one reading, where the same one
    /// refused on arrival is answered with a no and ends the sharing.
    ///
    /// Enforced at those two points rather than by the initialiser, so it binds
    /// what crosses the radio and not what a test may write down. A second
    /// sender would have to read it — `PulseRelay.report` is the only one today.
    static let plausible: ClosedRange<Int> = 25 ... 250

    /// Deliberately not the ack's or the notice's key. The three payloads travel
    /// through one decoder each, and distinct keys mean none can be read as
    /// another.
    private static let orderKey = "pulseOrderId"
    private static let rateKey = "beatsPerMinute"

    public var dictionary: [String: Any] {
        [Self.orderKey: orderId.uuidString, Self.rateKey: beatsPerMinute]
    }

    /// Nil for a payload missing either field, and for a rate no heart has.
    ///
    /// The band is checked here rather than trusted from the sender because this
    /// side is where a rate stops being a number: `PulseMonitor.receive` puts
    /// what arrives straight onto the badge and appends it to `PulseTrace`, so a
    /// decoding accident that happens to be an `Int` would draw as a heartbeat
    /// and shape the session's curve. A reading is worth nothing a moment later,
    /// which is what makes refusing one cheap.
    public init?(dictionary: [String: Any]) {
        guard let orderId = dictionary.uuid(Self.orderKey),
              let beatsPerMinute = dictionary[Self.rateKey] as? Int,
              Self.plausible.contains(beatsPerMinute)
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
