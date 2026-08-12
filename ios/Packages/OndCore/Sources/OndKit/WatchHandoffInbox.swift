import Foundation
import os

/// The watch's half of the pairing, minus the radio: everything the phone has
/// told this wrist about the person wearing it.
///
/// Here rather than in the watch target for the same reason the outbox is: what
/// `adopt` does is stateful, replayed on every activation, and silent when it
/// goes wrong — a watch left anonymous, or a mirrored personal best blanked by a
/// context that never carried one. The watch target has no test bundle, so
/// `PhoneLink` keeps the `WCSession` delegate callbacks and hands everything
/// they decode to this. The loudest of those failures is the last one it can
/// make: a context that says the person has deleted their account, ignored,
/// leaves the wrist syncing their erased practice back under a fresh identity.
@MainActor
@Observable
public final class WatchHandoffInbox {
    /// `watch-link`, the same category the phone's `WatchLink` files under:
    /// correlating a handoff that never arrived means reading one channel, not
    /// guessing at two names for the two ends of it.
    private static let logger = Logger(category: "watch-link")

    /// The identity now in hand, or nil while this watch is still anonymous.
    /// Observed rather than merely stored so the composition root can start a
    /// sync the moment one lands.
    public private(set) var userId: UUID?

    /// The phone's best controlled pause, or nil until a context has been read.
    ///
    /// Deliberately not persisted alongside the identity. The system already
    /// keeps the last `applicationContext` and replays it on every activation,
    /// so a copy in `UserDefaults` would be a second source of truth free to go
    /// stale against the first. What that costs is the fraction of a second
    /// between launch and activation with no number in hand — and the screen
    /// that shows it is two taps away.
    public private(set) var boltBestSeconds: Int?

    /// The session the phone has ordered and nothing has answered yet, or nil —
    /// which is almost always. Observed so the composition root can take it up
    /// the moment one is admitted, and consumed through `takeOrder()`.
    public private(set) var order: WatchSessionOrder?

    /// What the phone says the person is entitled to.
    ///
    /// Persisted, unlike the mirrored personal best above, and for the opposite
    /// reason: the best pause is a number on a screen two taps away, while this
    /// decides whether an order arriving in the same breath as a cold launch is
    /// acted on. The system replays the last context on activation, but the
    /// wrist can be asked to do something before that lands, and a wrist that
    /// answered "free" for the first half-second of every launch would decline
    /// a subscriber's session.
    ///
    /// Free until a phone has said otherwise, which is what an unpaired wrist,
    /// a first launch, and a mangled context all read as.
    public private(set) var entitledTier: SubscriptionTier {
        didSet {
            guard oldValue != entitledTier else { return }

            defaults.set(entitledTier.rawValue, forKey: Self.tierKey)
        }
    }

    private static let tierKey = "watch.entitledTier"

    private let identity: ProvisionedUserIdentityStore
    private let stores: [any PersonalStore]
    private let orders: WatchOrderLedger
    private let defaults: UserDefaults

    /// - Parameters:
    ///   - stores: what this wrist holds of its own — the sessions breathed on
    ///     it and the ledger of what has been sent — for the one context that
    ///     says the person they belonged to has been erased.
    ///   - orders: what stops a replayed context re-running its order. Passed
    ///     in rather than made here, because it is a third thing this wrist
    ///     persists and the root is where those are named.
    public init(
        identity: ProvisionedUserIdentityStore,
        stores: [any PersonalStore],
        orders: WatchOrderLedger,
        defaults: UserDefaults = .standard
    ) {
        self.identity = identity
        self.stores = stores
        self.orders = orders
        self.defaults = defaults
        userId = identity.userId()
        // Assigning in an initialiser does not run `didSet`, which is what keeps
        // this from writing back the value it just read.
        entitledTier = SubscriptionTier.cached(in: defaults, forKey: Self.tierKey)
    }

    /// Adopts a context, from wherever it arrived.
    ///
    /// Everything here is idempotent: the phone re-sends on every foreground, so
    /// the overwhelmingly common call is one that changes nothing.
    public func adopt(_ handoff: WatchHandoff) async {
        // The credential before the id, for the reason
        // `UserIdentityStore.adopt(sessionCredential:)` gives: a sync running
        // between the two writes must never send the new id with the old
        // credential, which is the one pairing the server refuses.
        identity.adopt(sessionCredential: handoff.sessionCredential)
        let changed = identity.adopt(handoff.userId)
        if changed {
            Self.logger.notice("adopted the phone's identity")
        }
        userId = identity.userId()

        // Only overwritten by a context that carries one: a phone whose owner
        // has not taken the test yet should not blank a number this watch was
        // given before. An erasure is the exception, and takes the `nil` with
        // everything else below.
        if let best = handoff.boltBestSeconds {
            boltBestSeconds = best
        }

        // Before the order, because it decides whether there is one to admit.
        entitledTier = handoff.entitledTier

        // The erasure before the order, and both after the identity. One context
        // can carry all three — a deletion's fresh id, its erase flag, and an
        // order, since the flag stands for as long as that identity does — and
        // an order admitted first would have a session recording into stores
        // being emptied underneath it.
        if changed, handoff.erasesPriorHistory {
            await erasePriorHistory()
        }

        // The subscription first, then the ledger. The phone already refuses to
        // place an order below `watchConnected`, so this is the receiving end of
        // the same rule rather than a second one: a context can outlive the
        // subscription that produced it — the system replays the last one on
        // every activation, for as long as the pairing lasts — and a lapsed
        // subscriber's wrist should stop taking up the errand it was last sent.
        // The ledger is what makes acting on replayed state safe at all: the
        // overwhelmingly common delivery is a context whose order has already
        // run, and it is refused here.
        guard handoff.entitledTier >= .watchConnected else { return }

        if let placed = handoff.order, orders.admit(placed) {
            order = placed
            Self.logger.notice("admitted a session order from the phone")
        }
    }

    /// Takes the order, leaving nothing behind.
    ///
    /// Consuming rather than reading, on `NotificationRouter.take()`'s pattern
    /// and for its reason: the wrist answers an order once, and a reader that
    /// left it in place would leave the caller to remember the clear on every
    /// path — including the ones that decline.
    public func takeOrder() -> WatchSessionOrder? {
        defer { order = nil }
        return order
    }

    /// Empties this wrist of the person the phone has just erased.
    ///
    /// Guarded on the identity having *actually changed*, which is what makes it
    /// safe to act on a flag the system will replay forever: the id a deletion
    /// minted becomes new to this watch exactly once, and every later delivery
    /// of the same context finds it already adopted and does nothing. Without
    /// that guard this would wipe the wrist's own practice on every activation
    /// until the person next signed in.
    ///
    /// The sessions are the reason this exists rather than the identity. A watch
    /// that only swapped ids would take its backlog — recorded under somebody
    /// who asked to be forgotten — and sync it straight into the fresh account
    /// they were given, which is a deletion that hands the history back.
    private func erasePriorHistory() async {
        for store in stores {
            await store.erase()
        }

        boltBestSeconds = nil
        Self.logger.notice("erased what this wrist held for a deleted account")
    }
}
