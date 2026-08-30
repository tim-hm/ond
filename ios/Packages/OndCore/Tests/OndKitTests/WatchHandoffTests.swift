import Foundation
import OndKit
import Testing

/// The phone-to-watch context, driven through the dictionary
/// WatchConnectivity actually carries. Worth pinning because both apps
/// encode it independently and the compiler checks neither: a renamed key
/// is invisible until a watch in someone's hand silently never receives
/// an identity.
@Suite("Watch handoff")
struct WatchHandoffTests {
    @Test("The context round-trips every field")
    func roundTripsEverything() throws {
        let sent = WatchHandoff(
            userId: UUID(),
            sessionCredential: "a-credential-the-phone-was-issued",
            boltBestSeconds: 42,
            erasesPriorHistory: true,
            agreedConsentVersion: 3
        )

        let received = try #require(WatchHandoff(dictionary: sent.dictionary))

        #expect(received == sent)
    }

    /// Deleting the account leaves the phone with nothing to read a version
    /// from, and the key has to go with it: the wrist reads absent as "no
    /// longer covered" and asks for the terms itself. A key that stayed behind
    /// would leave a deleted person's agreement standing on their watch.
    @Test("A phone that has agreed to nothing carries no version at all")
    func omitsAnAbsentConsentVersion() throws {
        let unasked = WatchHandoff(userId: UUID())

        #expect(!unasked.dictionary.keys.contains("agreedConsentVersion"))

        let decoded = try #require(WatchHandoff(dictionary: unasked.dictionary))
        #expect(decoded.agreedConsentVersion == nil)
    }

    /// The credential the wrist has to present once the phone has signed in; an
    /// absent one means "present nothing", not "keep what you have" — which is
    /// what makes a sign-out reach the watch at all. Pinned separately because
    /// absence is the state most contexts are in, and a key that only worked
    /// when populated would leave the wrist presenting a revoked value forever.
    @Test("A context with no credential carries the key at all")
    func omitsAnAbsentCredential() throws {
        let anonymous = WatchHandoff(userId: UUID())

        #expect(!anonymous.dictionary.keys.contains("sessionCredential"))

        let decoded = try #require(WatchHandoff(dictionary: anonymous.dictionary))
        #expect(decoded.sessionCredential == nil)
    }

    /// The erasure flag is the one field whose two values are not symmetrical.
    /// Read as true where the phone meant nothing of the kind, it wipes a
    /// person's practice off their wrist — so an absent, misspelled or
    /// mistyped key has to read as false, and does.
    @Test("An erasure nobody asked for cannot be read out of a context")
    func defaultsToKeepingTheHistory() throws {
        let id = UUID()
        let ordinary: [[String: Any]] = [
            ["userId": id.uuidString],
            ["userId": id.uuidString, "erasesPriorHistory": "true"],
            ["userId": id.uuidString, "erasesPriorHistroy": true],
        ]

        for context in ordinary {
            let decoded = try #require(WatchHandoff(dictionary: context))
            #expect(decoded.erasesPriorHistory == false)
        }

        #expect(
            !WatchHandoff(userId: id).dictionary.keys.contains("erasesPriorHistory"),
            "an ordinary context should not carry the key at all"
        )
    }

    /// The common case for a long time: somebody breathing on the wrist who has
    /// never taken a controlled-pause test.
    @Test("A handoff with no BOLT score round-trips as no score")
    func roundTripsWithoutAScore() throws {
        let sent = WatchHandoff(userId: UUID())

        let context = sent.dictionary
        let received = try #require(WatchHandoff(dictionary: context))

        #expect(received.boltBestSeconds == nil)
        #expect(context.count == 1, "an absent score should not travel as a key at all")
    }

    /// A zero is what a phone with an empty score file would send if anything
    /// ever summed rather than maxed. Nobody held their breath for no seconds,
    /// so it must not surface as a personal best on the wrist — whichever side
    /// of the wire the zero came in on.
    @Test("A zero-second best is no best, however it arrives")
    func rejectsAZeroScore() throws {
        let id = UUID()
        let context: [String: Any] = ["userId": id.uuidString, "boltBestSeconds": 0]

        let decoded = try #require(WatchHandoff(dictionary: context))

        #expect(decoded.boltBestSeconds == nil)
        #expect(
            WatchHandoff(userId: id, boltBestSeconds: 0) == WatchHandoff(userId: id),
            "a zero and an absence describe the same person, so they must compare equal"
        )
    }

    /// The one field that is itself a dictionary: the session order the phone
    /// wants the wrist to run. Every field of it matters — the id is the
    /// ledger's replay guard and the issue date is the freshness window — so
    /// the nested codec is pinned through the outer one it always travels in.
    @Test("A context carrying a session order round-trips it whole")
    func roundTripsAnOrder() throws {
        let order = WatchSessionOrder(
            id: UUID(),
            errand: .breathe(
                occasionSlug: "through-this-meeting",
                techniqueSlug: "coherent-breathing"
            ),
            issuedAt: Date(timeIntervalSince1970: 1_754_900_000)
        )
        let sent = WatchHandoff(userId: UUID(), order: order)

        let received = try #require(WatchHandoff(dictionary: sent.dictionary))

        #expect(received.order == order)
        #expect(
            !WatchHandoff(userId: UUID()).dictionary.keys.contains("order"),
            "an ordinary context should not carry the key at all"
        )
    }

    /// A malformed order must not take the identity down with it: the context
    /// still provisions the wrist, and only the order reads as absent.
    @Test("A context with a broken order still hands over the identity")
    func survivesABrokenOrder() throws {
        let id = UUID()
        let context: [String: Any] = [
            "userId": id.uuidString,
            "order": ["id": "not-a-uuid"],
        ]

        let decoded = try #require(WatchHandoff(dictionary: context))

        #expect(decoded.userId == id)
        #expect(decoded.order == nil)
    }

    /// The watch must not adopt an identity it cannot use — a half-read context
    /// is ignored, leaving it anonymous rather than attributing sessions to
    /// something the server will reject.
    @Test("A context with no usable id is refused")
    func refusesAnUnusableContext() {
        // Written as a loop rather than `@Test(arguments:)` because a case here
        // is a `[String: Any]`, which Swift Testing cannot carry across the
        // isolation boundary a parameterised test runs each case in.
        let unusable: [[String: Any]] = [
            [:],
            ["userId": "not-a-uuid"],
            ["boltBestSeconds": 30],
        ]

        for context in unusable {
            #expect(WatchHandoff(dictionary: context) == nil)
        }
    }
}
