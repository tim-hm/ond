import Foundation
import OndKit
import os
import Testing

/// A radio that never works, standing in for a phone whose watch has just been
/// unpaired or whose session refused the context.
private struct DeadRadio: Error {}

/// The phone's half of the handoff: what is worth sending, and what has already
/// been sent.
///
/// Worth pinning because both failure modes are silent. Sending an unchanged
/// context on every foreground wakes the watch to deliver news it already has;
/// recording one as delivered when it was not leaves a watch permanently one
/// context behind, with nothing on either screen to say so.
@MainActor
@Suite("Watch handoff outbox")
struct WatchHandoffOutboxTests {
    /// Collects what the outbox offers, standing in for `WCSession`.
    private final class Radio {
        private(set) var handed: [WatchHandoff] = []

        func accept(_ handoff: WatchHandoff) {
            handed.append(handoff)
        }
    }

    @Test("A phone with no identity yet has nothing to hand over")
    func waitsForAnIdentity() async {
        let radio = Radio()
        let outbox = WatchHandoffOutbox(
            identity: StubIdentity(id: nil),
            scores: StubScores(seconds: [30])
        )

        await outbox.handOver(radio.accept)

        #expect(radio.handed.isEmpty)
    }

    @Test("The first context carries the identity and the best pause")
    func handsOverTheFirstContext() async throws {
        let id = UUID()
        let radio = Radio()
        let outbox = WatchHandoffOutbox(
            identity: StubIdentity(id: id),
            scores: StubScores(seconds: [22, 41, 19])
        )

        await outbox.handOver(radio.accept)

        let handoff = try #require(radio.handed.first)
        #expect(handoff.userId == id)
        #expect(handoff.boltBestSeconds == 41, "the best of them, not the last")
    }

    /// A credential the phone was issued is news, and so is losing one.
    ///
    /// The dedupe compares whole contexts, so this works by construction — which
    /// is exactly why it is worth pinning: a field added to `WatchHandoff`
    /// without `Equatable` noticing would leave the wrist on the last context
    /// that happened to differ in some other way.
    @Test("A credential the phone gained or lost is a context worth sending")
    func handsOverAChangedCredential() async {
        let radio = Radio()
        let identity = StubIdentity(id: UUID())
        let outbox = WatchHandoffOutbox(identity: identity, scores: StubScores())

        await outbox.handOver(radio.accept)

        identity.adopt(sessionCredential: "issued-by-a-sign-in")
        await outbox.handOver(radio.accept)

        identity.adopt(sessionCredential: nil)
        await outbox.handOver(radio.accept)

        #expect(radio.handed.count == 3)
        #expect(radio.handed.map(\.sessionCredential) == [nil, "issued-by-a-sign-in", nil])
    }

    /// The phone pushes on every foreground and almost none of them carry news.
    /// `updateApplicationContext` wakes the watch to deliver whatever it is
    /// given, so an unchanged context is radio time spent on nothing.
    @Test("An unchanged context is not handed over twice")
    func deduplicatesAnUnchangedContext() async {
        let radio = Radio()
        let outbox = WatchHandoffOutbox(
            identity: StubIdentity(id: UUID()),
            scores: StubScores(seconds: [30])
        )

        await outbox.handOver(radio.accept)
        await outbox.handOver(radio.accept)

        #expect(radio.handed.count == 1)
    }

    /// The other half of the same rule: a send that threw was never delivered, so
    /// the context has to still be outstanding when the next foreground asks.
    @Test("A hand-over that threw is offered again")
    func retriesAFailedHandover() async {
        let radio = Radio()
        let outbox = WatchHandoffOutbox(
            identity: StubIdentity(id: UUID()),
            scores: StubScores(seconds: [30])
        )

        try? await outbox.handOver { _ in throw DeadRadio() }
        await outbox.handOver(radio.accept)

        #expect(radio.handed.count == 1)
    }

    /// The reason the phone pushes at all after the first launch: a BOLT test
    /// taken on the phone has to reach the wrist, which cannot measure one.
    @Test("A new personal best is handed over")
    func handsOverANewBest() async {
        let radio = Radio()
        let scores = StubScores(seconds: [30])
        let outbox = WatchHandoffOutbox(identity: StubIdentity(id: UUID()), scores: scores)

        await outbox.handOver(radio.accept)
        await scores.record(BoltScore(seconds: 45))
        await outbox.handOver(radio.accept)

        #expect(radio.handed.map(\.boltBestSeconds) == [30, 45])
    }

    /// The wrist carries its own copy of the identity and caches it, so a
    /// sign-in that swapped the phone's leaves the watch syncing to a row the
    /// server has deleted — for as long as nothing tells it otherwise. What
    /// tells it is this context, which is only sent because the outbox compares
    /// what it holds rather than assuming an identity never changes.
    @Test("An identity replaced by a sign-in is handed over")
    func handsOverASwappedIdentity() async {
        let radio = Radio()
        let identity = StubIdentity(id: UUID())
        let outbox = WatchHandoffOutbox(identity: identity, scores: StubScores(seconds: [30]))

        await outbox.handOver(radio.accept)
        let adopted = UUID()
        identity.adopt(adopted)
        await outbox.handOver(radio.accept)

        #expect(radio.handed.count == 2)
        #expect(radio.handed.last?.userId == adopted)
    }

    /// The context that tells the wrist a person is gone, rather than merely
    /// filed under a different name.
    ///
    /// It has to survive a relaunch, which is why it is on disk: a watch can be
    /// off, out of range or unpaired for days after somebody deletes their
    /// account, and a marker that lived for the process would leave it holding
    /// their practice with nothing left to tell it otherwise.
    @Test("A deletion is handed over as an erasure, and goes on being one")
    func handsOverAnErasureUntilTheIdentityChangesAgain() async throws {
        let radio = Radio()
        let identity = StubIdentity(id: UUID())
        let defaults = try #require(
            UserDefaults(suiteName: "outbox-tests.erasure.\(UUID().uuidString)")
        )
        let outbox = WatchHandoffOutbox(
            identity: identity,
            scores: StubScores(),
            defaults: defaults
        )

        // What a deletion does, in the order `AccountModel` does it: mint, then
        // empty everything that holds anything.
        identity.adopt(UUID())
        await outbox.erase()
        await outbox.handOver(radio.accept)

        #expect(radio.handed.last?.erasesPriorHistory == true)

        // A fresh process, which is what a relaunch before the watch is next in
        // range amounts to.
        let relaunched = WatchHandoffOutbox(
            identity: identity,
            scores: StubScores(),
            defaults: defaults
        )
        await relaunched.handOver(radio.accept)

        #expect(radio.handed.last?.erasesPriorHistory == true)
    }

    /// The marker is stored as the identity it belongs to rather than as a flag,
    /// so it expires by itself: the next sign-in or sign-out mints another id
    /// and the contexts that follow are ordinary again, with nothing anywhere
    /// having to remember to clear it.
    @Test("An identity minted after the deletion is handed over as an ordinary one")
    func stopsErasingOnceTheIdentityMovesOn() async throws {
        let radio = Radio()
        let identity = StubIdentity(id: UUID())
        let defaults = try #require(
            UserDefaults(suiteName: "outbox-tests.expiry.\(UUID().uuidString)")
        )
        let outbox = WatchHandoffOutbox(
            identity: identity,
            scores: StubScores(),
            defaults: defaults
        )

        identity.adopt(UUID())
        await outbox.erase()
        await outbox.handOver(radio.accept)

        identity.adopt(UUID())
        await outbox.handOver(radio.accept)

        #expect(radio.handed.map(\.erasesPriorHistory) == [true, false])
    }

    /// The launch call carries no payload, so the order rides the context out
    /// — and because the dedupe compares whole contexts, placing one is what
    /// makes the next push worth sending at all.
    @Test("A placed order rides the next context, and a withdrawn one does not")
    func carriesAPlacedOrderUntilItIsWithdrawn() async {
        let radio = Radio()
        let outbox = WatchHandoffOutbox(
            identity: StubIdentity(id: UUID()),
            scores: StubScores()
        )
        let order = WatchSessionOrder(
            id: UUID(),
            errand: .breathe(
                occasionSlug: "through-this-meeting",
                techniqueSlug: "coherent-breathing"
            ),
            issuedAt: .now
        )

        await outbox.handOver(radio.accept)
        outbox.place(order)
        await outbox.handOver(radio.accept)

        #expect(radio.handed.map(\.order) == [nil, order])

        outbox.withdraw(order.id)
        await outbox.handOver(radio.accept)

        #expect(radio.handed.last?.order == nil, "the concluded order is no longer news")
    }

    /// A conclusion can outlive its exchange: the timeout gives up, the person
    /// re-taps, and the stale conclusion's withdrawal arrives after the newer
    /// placement. It must not take the newer order with it.
    @Test("A stale withdrawal does not remove a newer order")
    func keepsANewerOrderThroughAStaleWithdrawal() async {
        let radio = Radio()
        let outbox = WatchHandoffOutbox(
            identity: StubIdentity(id: UUID()),
            scores: StubScores()
        )
        let first = WatchSessionOrder(
            id: UUID(),
            errand: .breathe(
                occasionSlug: "through-this-meeting",
                techniqueSlug: "coherent-breathing"
            ),
            issuedAt: .now
        )
        let second = WatchSessionOrder(
            id: UUID(),
            errand: .breathe(
                occasionSlug: "through-this-meeting",
                techniqueSlug: "coherent-breathing"
            ),
            issuedAt: .now
        )

        outbox.place(first)
        outbox.place(second)
        outbox.withdraw(first.id)
        await outbox.handOver(radio.accept)

        #expect(radio.handed.last?.order == second)
    }

    /// A worse score is not news. The watch mirrors the best, so a later, shorter
    /// pause leaves the context exactly as it was.
    @Test("A worse score is not news")
    func ignoresAWorseScore() async {
        let radio = Radio()
        let scores = StubScores(seconds: [45])
        let outbox = WatchHandoffOutbox(identity: StubIdentity(id: UUID()), scores: scores)

        await outbox.handOver(radio.accept)
        await scores.record(BoltScore(seconds: 12))
        await outbox.handOver(radio.accept)

        #expect(radio.handed.count == 1)
    }
}
