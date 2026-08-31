import Foundation
@testable import OndKit
import Testing

/// The two payloads a shared pulse travels as, and the order errand that
/// starts one. Codecs get tests here for the reason the rest of the pairing's
/// do: the two devices agree on key names down to the character, nothing in
/// the type system checks that, and a key read wrongly is a badge that never
/// appears with no error anywhere to say why.
@Suite("Watch pulse payloads")
struct WatchPulseTests {
    @Test("A reading survives the round trip")
    func readingRoundTrips() throws {
        let pulse = WatchPulse(orderId: UUID(), beatsPerMinute: 62)

        let decoded = try #require(WatchPulse(dictionary: pulse.dictionary))

        #expect(decoded == pulse)
    }

    @Test("A reply survives the round trip, both ways round")
    func replyRoundTrips() throws {
        for isWanted in [true, false] {
            let reply = WatchPulseReply(isWanted: isWanted)
            let decoded = try #require(WatchPulseReply(dictionary: reply.dictionary))
            #expect(decoded.isWanted == isWanted)
        }
    }

    /// The three inbound payloads pass through one decoder each and arrive on two
    /// channels, so a key shared between any two of them would let the wrong
    /// decoder claim a message. The ack's is the one that matters most: it and a
    /// reading both ride `sendMessage`.
    @Test("A reading, an ack, and a notice cannot be read as each other")
    func payloadsDoNotCollide() {
        let id = UUID()
        let pulse = WatchPulse(orderId: id, beatsPerMinute: 62).dictionary
        let ack = WatchOrderAck(orderId: id, accepted: true).dictionary
        let notice = WatchSessionNotice(orderId: id).dictionary

        #expect(WatchOrderAck(dictionary: pulse) == nil)
        #expect(WatchSessionNotice(dictionary: pulse) == nil)
        #expect(WatchPulse(dictionary: ack) == nil)
        #expect(WatchPulse(dictionary: notice) == nil)
    }

    @Test("A reading missing its rate is no reading at all")
    func refusesAHalfReading() {
        var half = WatchPulse(orderId: UUID(), beatsPerMinute: 62).dictionary
        half["beatsPerMinute"] = nil

        #expect(WatchPulse(dictionary: half) == nil)
    }

    /// The phone puts what this decoder returns straight onto the badge and into
    /// the session's pulse curve, so a number that is not a heart rate has to
    /// fail here rather than arrive as one. Nothing on the receiving side asks
    /// again.
    @Test("A rate no heart has is no reading")
    func refusesAnImplausibleRate() {
        let reading = WatchPulse(orderId: UUID(), beatsPerMinute: 62).dictionary

        for rate in [0, -60, 9000, 24, 251] {
            var implausible = reading
            implausible["beatsPerMinute"] = rate

            #expect(WatchPulse(dictionary: implausible) == nil, "\(rate) is not a heart rate")
        }

        for rate in [25, 250] {
            var edge = reading
            edge["beatsPerMinute"] = rate

            #expect(WatchPulse(dictionary: edge)?.beatsPerMinute == rate, "\(rate) is one")
        }
    }

    @Test("An unreadable reply is not a reply")
    func refusesAnUnreadableReply() {
        #expect(WatchPulseReply(dictionary: [:]) == nil)
        #expect(WatchPulseReply(dictionary: ["wantsPulse": "yes"]) == nil)
    }

    /// Both errands ride the one context, so the codec has to tell them apart on
    /// nothing but the kind it wrote.
    @Test("Both errands survive the round trip")
    func errandsRoundTrip() throws {
        let errands: [WatchSessionOrder.Errand] = [
            .breathe(occasionSlug: "through-this-meeting", techniqueSlug: "coherent-breathing"),
            .sharePulse,
        ]

        for errand in errands {
            let order = WatchSessionOrder(id: UUID(), errand: errand, issuedAt: .now)
            let decoded = try #require(WatchSessionOrder(dictionary: order.dictionary))
            #expect(decoded.errand == errand)
            #expect(decoded.id == order.id)
        }
    }

    /// A reading errand carries no slugs, so nothing may resolve it into a
    /// session: `OrderedMoment` is the one gate between an order and a technique.
    @Test("A reading errand never resolves into something to breathe")
    func sharingIsNotASession() {
        let order = WatchSessionOrder(id: UUID(), errand: .sharePulse, issuedAt: .now)

        #expect(
            OrderedMoment(
                order: order,
                techniques: SeededCatalogue.techniques,
                occasions: []
            ) == nil,
            "a wrist asked for its sensor must not start breathing"
        )
    }

    /// An older watch reading a newer phone's context. Nil rather than a guess:
    /// the alternative is a wrist performing whichever errand this build happens
    /// to default to.
    @Test("An errand this build does not know is no order")
    func refusesAnUnknownErrand() {
        var unknown = WatchSessionOrder(id: UUID(), errand: .sharePulse, issuedAt: .now).dictionary
        unknown["kind"] = "somethingElse"

        #expect(WatchSessionOrder(dictionary: unknown) == nil)
    }

    /// The two paces are set in different types and have to stay in step: the
    /// phone must not call a reading stale while the wrist is still holding the
    /// next one back.
    /// `@MainActor` for the constants alone: both belong to models that live
    /// there, and this is the one test in the suite that reads a model at all.
    @MainActor
    @Test("The phone waits longer than the wrist takes to send again")
    func freshnessOutlastsTheWristsPacing() {
        #expect(PulseMonitor.staleness > PulseRelay.spacing * 2)
        #expect(PulseRelay.silence > PulseMonitor.staleness)
    }
}
