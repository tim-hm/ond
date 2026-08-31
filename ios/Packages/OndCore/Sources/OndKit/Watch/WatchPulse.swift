import Foundation

/// One heart-rate reading, on its way from the wrist to a session on the
/// phone. Worth nothing a moment later, so a reading that cannot be
/// delivered is dropped and the next goes instead. No timestamp travels with
/// it: the phone times the arrival on its own clock, and a field nobody
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

    /// What a heart rate can be, either side of the radio. A decode check,
    /// not a clinical one: it catches numbers that are no heart rate at all —
    /// zero arrives in practice, the sensor saying nothing. A reading dropped
    /// at the wrist costs one reading; one refused on arrival ends the
    /// sharing. Binds the radio, not the initialiser, so tests may write any.
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
    /// Checked here rather than trusted from the sender:
    /// `PulseMonitor.receive` puts what arrives straight onto the badge and
    /// into `PulseTrace`, so a decoding accident that happens to be an `Int`
    /// would draw as a heartbeat.
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

/// The phone's answer to a reading: whether it still wants them. Every
/// reading carries its own reply — a wrist still sending has just reached
/// the phone, so the reply is the one moment the news is guaranteed to
/// travel. A relaunched phone with no session answers no and the wrist puts
/// the sensor down, where a "stop" never sent would leave a workout running.
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
