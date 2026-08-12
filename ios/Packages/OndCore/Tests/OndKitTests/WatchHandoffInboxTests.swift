import Foundation
@testable import OndKit
import Testing

/// The watch's half of the handoff: what the wrist does with a context once it
/// has one.
///
/// Worth pinning because the phone re-sends on every foreground and the system
/// replays the last context on every activation, so `adopt` is called far more
/// often than anything changes — and each of the rules below is one that only
/// shows itself on the replay. A watch left anonymous, or a mirrored best
/// blanked by a context that never carried one, looks from the outside like a
/// screen that simply has no number on it.
@MainActor
@Suite("Watch handoff inbox")
struct WatchHandoffInboxTests {
    @Test("A watch that has never met its phone is anonymous, with no best")
    func startsAnonymous() {
        let inbox =
            inbox(storage: FakeStorage())

        #expect(inbox.userId == nil)
        #expect(inbox.boltBestSeconds == nil)
    }

    /// The launch that covers most launches: the identity is already stored, and
    /// the screens are drawn before `WCSession` has activated. Reading it in the
    /// initialiser is what keeps that first frame attributable.
    @Test("A stored identity is in hand before any context arrives")
    func readsTheStoredIdentityAtOnce() {
        let id = UUID()
        let inbox = inbox(storage: FakeStorage(holding: id))

        #expect(inbox.userId == id)
    }

    @Test("A context hands over the identity and the phone's best pause")
    func adoptsAContext() async {
        let inbox =
            inbox(storage: FakeStorage())
        let id = UUID()

        await inbox.adopt(WatchHandoff(userId: id, boltBestSeconds: 38))

        #expect(inbox.userId == id)
        #expect(inbox.boltBestSeconds == 38)
    }

    /// The credential travels with the id, and a context without one clears
    /// whatever the wrist was holding.
    ///
    /// Both halves matter and both are invisible from a screen. Without the
    /// first, a watch whose phone has signed in is refused every sync it
    /// attempts — the identity they share is bound now, and possession of it
    /// stopped being enough. Without the second, a phone that signed out leaves
    /// the wrist presenting a value the server has already revoked, which is the
    /// same refusal reached from the other direction.
    @Test("A context hands over the credential too, and an empty one takes it back")
    func adoptsTheCredential() async {
        let identity = ProvisionedUserIdentityStore(storage: FakeStorage())
        let inbox = inbox(identity: identity)

        await inbox.adopt(WatchHandoff(userId: UUID(), sessionCredential: "issued-on-the-phone"))
        #expect(identity.sessionCredential() == "issued-on-the-phone")

        await inbox.adopt(WatchHandoff(userId: UUID()))
        #expect(
            identity.sessionCredential() == nil,
            "the phone signed out, so the wrist holds nothing that proves the account"
        )
    }

    /// The system replays the last `applicationContext` on every activation and
    /// the phone re-sends on every foreground, so the overwhelmingly common call
    /// is one that must change nothing.
    @Test("Re-adopting the same context changes nothing")
    func isIdempotent() async {
        let inbox =
            inbox(storage: FakeStorage())
        let handoff = WatchHandoff(userId: UUID(), boltBestSeconds: 38)

        await inbox.adopt(handoff)
        await inbox.adopt(handoff)

        #expect(inbox.userId == handoff.userId)
        #expect(inbox.boltBestSeconds == 38)
    }

    /// The rule that only bites on a replay: a phone whose owner has not taken
    /// the test yet sends a context with no score in it, and that must not blank
    /// a number this watch was already given.
    @Test("A context with no best does not blank the one already held")
    func keepsABestASilentContextOmits() async {
        let inbox =
            inbox(storage: FakeStorage())
        let id = UUID()

        await inbox.adopt(WatchHandoff(userId: id, boltBestSeconds: 38))
        await inbox.adopt(WatchHandoff(userId: id))

        #expect(inbox.boltBestSeconds == 38)
    }

    /// Somebody who reinstalled the phone app arrives with a new id. The phone is
    /// the authority on who this person is, so the wrist follows it rather than
    /// syncing to an identity nothing else writes to.
    @Test("A new identity from the phone replaces the old one")
    func followsThePhoneToANewIdentity() async {
        let storage = FakeStorage(holding: UUID())
        let inbox = inbox(storage: storage)
        let replacement = UUID()

        await inbox.adopt(WatchHandoff(userId: replacement))

        #expect(inbox.userId == replacement)
        #expect(storage.read() == replacement, "and it survives the next launch")
    }

    /// The deletion, from the wrist's side. Without this the watch keeps the
    /// erased person's sessions and syncs them straight back up under the fresh
    /// identity it has just been handed — a deletion that returns the history it
    /// deleted.
    @Test("A context that replaces a deleted identity empties the wrist")
    func erasesWhatADeletedAccountLeftBehind() async {
        let store = CountingStore()
        let inbox = inbox(storage: FakeStorage(holding: UUID()), stores: [store])

        await inbox.adopt(WatchHandoff(userId: UUID(), boltBestSeconds: 41))
        await inbox.adopt(WatchHandoff(userId: UUID(), erasesPriorHistory: true))

        #expect(store.erasures == 1)
        #expect(inbox.boltBestSeconds == nil, "the best pause belonged to the person erased")
    }

    /// The rule that makes a flag safe to carry in a context the system replays
    /// forever: the erasure is guarded on the identity having actually changed,
    /// so every later delivery of the same context finds it already adopted.
    ///
    /// Without the guard, a watch would wipe its own practice on every
    /// activation for as long as the phone carried that identity — which is
    /// until the person next signs in, and possibly never.
    @Test("A replayed erasure does not wipe what the wrist has done since")
    func erasesOnlyOnce() async {
        let store = CountingStore()
        let inbox = inbox(stores: [store])
        let handoff = WatchHandoff(userId: UUID(), erasesPriorHistory: true)

        await inbox.adopt(handoff)
        await inbox.adopt(handoff)
        await inbox.adopt(handoff)

        #expect(store.erasures == 1)
    }

    /// The other half of the same rule. Signing in hands the wrist a different
    /// id and its unsent sessions go up under that one, which is where the
    /// person's practice now lives — so an ordinary swap must erase nothing.
    @Test("An identity swapped by a sign-in erases nothing")
    func keepsThePracticeThroughAnOrdinarySwap() async {
        let store = CountingStore()
        let inbox = inbox(storage: FakeStorage(holding: UUID()), stores: [store])

        await inbox.adopt(WatchHandoff(userId: UUID(), boltBestSeconds: 41))

        #expect(store.erasures == 0)
        #expect(inbox.boltBestSeconds == 41)
    }

    /// The phone's order arrives inside the same context as everything else,
    /// and the identity it travelled with must land first: the session the
    /// order composes records under whoever the context says the person is.
    @Test("A fresh order is admitted, alongside the identity it came with")
    func admitsAFreshOrder() async {
        let id = UUID()
        let inbox = inbox()
        let order = WatchSessionOrder(
            id: UUID(),
            errand: .breathe(
                occasionSlug: "through-this-meeting",
                techniqueSlug: "coherent-breathing"
            ),
            issuedAt: .now
        )

        await inbox.adopt(WatchHandoff(userId: id, order: order))

        #expect(inbox.order == order)
        #expect(inbox.userId == id)
    }

    /// The rule the ledger exists for, seen from the inbox: the system replays
    /// the last context on every activation, and a session that ran must not
    /// run again — even after the screen has consumed and cleared the order.
    @Test("A replayed context does not re-admit its order")
    func refusesAReplayedOrder() async {
        let inbox = inbox()
        let handoff = WatchHandoff(
            userId: UUID(),
            order: WatchSessionOrder(
                id: UUID(),
                errand: .breathe(
                    occasionSlug: "through-this-meeting",
                    techniqueSlug: "coherent-breathing"
                ),
                issuedAt: .now
            )
        )

        await inbox.adopt(handoff)
        #expect(inbox.takeOrder() != nil, "taken up once")
        await inbox.adopt(handoff)

        #expect(inbox.order == nil)
    }

    /// A context nobody delivered for an afternoon still arrives eventually,
    /// and its order must arrive dead: a wrist activating at midnight owes
    /// nobody the meeting session from lunchtime.
    @Test("A stale order is not admitted at all")
    func refusesAStaleOrder() async {
        let inbox = inbox()
        let stale = WatchSessionOrder(
            id: UUID(),
            errand: .breathe(
                occasionSlug: "through-this-meeting",
                techniqueSlug: "coherent-breathing"
            ),
            issuedAt: Date(timeIntervalSinceNow: -(WatchOrderLedger.freshness + 60))
        )

        await inbox.adopt(WatchHandoff(userId: UUID(), order: stale))

        #expect(inbox.order == nil)
    }

    /// An inbox whose order ledger writes to a throwaway suite, so admissions in
    /// one test cannot leak into the next.
    private func inbox(
        identity: ProvisionedUserIdentityStore? = nil,
        storage: FakeStorage = FakeStorage(),
        stores: [any PersonalStore] = []
    ) -> WatchHandoffInbox {
        WatchHandoffInbox(
            identity: identity ?? ProvisionedUserIdentityStore(storage: storage),
            stores: stores,
            orders: WatchOrderLedger(
                defaults: UserDefaults(suiteName: "inbox-tests.\(UUID().uuidString)") ?? .standard
            )
        )
    }
}

/// A store that only records having been emptied. What each real one does with
/// its own files and keys is pinned beside those; what matters here is *whether*
/// the inbox asks, and exactly once.
@MainActor
private final class CountingStore: PersonalStore {
    private(set) var erasures = 0

    func erase() async {
        erasures += 1
    }
}
