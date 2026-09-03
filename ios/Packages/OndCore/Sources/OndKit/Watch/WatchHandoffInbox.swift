import Foundation
import os

/// Everything the phone has told this wrist about the person wearing it.
/// Here rather than in the watch target because that target has no test
/// bundle: `PhoneLink` keeps the `WCSession` delegate callbacks and hands
/// what they decode to this. What `adopt` does is replayed on every
/// activation and silent when wrong, so host tests have to pin it.
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
    public private(set) var userId: UserId?

    /// The phone's best controlled pause, or nil until a context has been
    /// read. Deliberately not persisted: the system replays the last
    /// `applicationContext` on every activation, and a `UserDefaults` copy
    /// would be a second source of truth free to go stale against it.
    public private(set) var boltBestSeconds: Int?

    /// The session the phone has ordered and nothing has answered yet, or nil —
    /// which is almost always. Observed so the composition root can take it up
    /// the moment one is admitted, and consumed through `takeOrder()`.
    public private(set) var order: WatchSessionOrder?

    /// What the phone says the person is entitled to. Persisted, unlike the
    /// mirrored best above: an order can arrive before the replayed context
    /// lands on a cold launch, and a wrist answering "free" for that first
    /// half-second would decline a subscriber's session. Free until a phone
    /// has said otherwise.
    public private(set) var entitledTier: SubscriptionTier {
        didSet {
            guard oldValue != entitledTier else { return }

            defaults.set(entitledTier.rawValue, forKey: Self.tierKey)
        }
    }

    /// The `SafetyConsent.version` the phone's owner agreed to, or nil while
    /// this wrist has been told of no agreement. Persisted on the tier's
    /// reasoning: the replayed context lands a moment after a cold launch, and
    /// a wrist answering "nothing known" until then would show the terms to
    /// somebody who has already agreed to them on their phone.
    public private(set) var agreedConsentVersion: Int? {
        didSet {
            guard oldValue != agreedConsentVersion else { return }

            defaults.set(agreedConsentVersion, forKey: Self.consentKey)
        }
    }

    private static let tierKey = "watch.entitledTier"
    private static let consentKey = "watch.agreedConsentVersion"

    private let identity: ProvisionedUserIdentityStore
    private let stores: [any PersonalStore]
    private let orders: WatchOrderLedger
    private let defaults: UserDefaults

    /// - Parameters:
    ///   - stores: what this wrist holds of its own, for the one context that
    ///     says the person they belonged to has been erased.
    ///   - orders: what stops a replayed context re-running its order. Made
    ///     in the root, where everything this wrist persists is named.
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
        agreedConsentVersion = defaults.object(forKey: Self.consentKey) as? Int
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
        let changed = identity.adopt(userId: handoff.userId)
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

        // Unlike the best pause above, a context that carries nothing does
        // blank this. Deleting the account is how an agreement goes away, and
        // it leaves the phone with no version to send — so absent has to mean
        // "the phone no longer covers this wrist", not "no news".
        agreedConsentVersion = handoff.agreedConsentVersion

        // Before the order, because it decides whether there is one to admit.
        // Guarded, unlike the two above: the wrist's screens read this one, and
        // Observation publishes every assignment — an unguarded write would
        // invalidate them on each of the phone's foregrounds.
        if entitledTier != handoff.entitledTier {
            entitledTier = handoff.entitledTier
        }

        // The erasure before the order, and both after the identity. One context
        // can carry all three — a deletion's fresh id, its erase flag, and an
        // order, since the flag stands for as long as that identity does — and
        // an order admitted first would have a session recording into stores
        // being emptied underneath it.
        if changed, handoff.erasesPriorHistory {
            await erasePriorHistory()
        }

        // The receiving end of the phone's rule not to place orders below
        // `watchConnected`: the system replays the last context for as long
        // as the pairing lasts, so it can outlive the subscription that
        // produced it, and a lapsed wrist should drop the errand. The ledger
        // then refuses the order on every replay after it has run.
        guard handoff.entitledTier >= .watchConnected else { return }

        if let placed = handoff.order, orders.admit(placed) {
            order = placed
            Self.logger.notice("admitted a session order from the phone")
        }
    }

    /// Takes the order, leaving nothing behind. Consuming rather than
    /// reading, as `NotificationRouter.take()` is: the wrist answers an order
    /// once, and a reader would leave every caller — declining paths included
    /// — to remember the clear.
    public func takeOrder() -> WatchSessionOrder? {
        defer { order = nil }
        return order
    }

    /// Empties this wrist of the person the phone has just erased. Guarded on
    /// the identity having actually changed, which makes a flag the system
    /// replays forever safe: without the guard this would wipe the wrist on
    /// every activation. The sessions are the point — left in place, the
    /// backlog would sync a forgotten person's history into the fresh account.
    private func erasePriorHistory() async {
        for store in stores {
            await store.erase()
        }

        boltBestSeconds = nil
        Self.logger.notice("erased what this wrist held for a deleted account")
    }
}
