import Foundation

/// The phone's half of the pairing, minus the radio: what the watch is owed,
/// what it has already been told, and the one thing it is owed across a
/// relaunch.
///
/// Here rather than in the app target because the deduplication below is the
/// point of the phone's `WatchLink` and its failure mode is "nothing happened" —
/// either a context that stops being sent when it should not, or one re-sent on
/// every foreground, waking a watch to deliver news it already has. Neither
/// shows up on a screen, and the app target has no test bundle. `WatchLink`
/// keeps the `WCSession` calls and nothing else.
@MainActor
public final class WatchHandoffOutbox: PersonalStore {
    /// The identity a deletion minted, so the context that carries it can say
    /// what it replaced.
    ///
    /// On disk rather than in memory, because the wrist may be off, out of range
    /// or unpaired for days after somebody deletes their account, and the phone
    /// is very likely to be relaunched in between. A flag that lived for the
    /// process would leave the watch holding an erased person's practice with
    /// nothing left anywhere to tell it otherwise.
    private static let erasedKey = "watch.identityAfterDeletion"

    private let identity: any UserIdentityStore
    private let scores: any BoltScoreRecording
    private let defaults: UserDefaults

    /// What the person is entitled to, read at hand-over rather than held.
    ///
    /// A closure rather than the `SubscriptionStore` itself, on the seam this
    /// type already keeps everywhere else: what it needs is one value, and
    /// taking the store would put `StoreKit`'s whole surface behind a type
    /// whose tests have no App Store account. Read per hand-over so a purchase
    /// made a moment ago is what the wrist is told about.
    private let entitledTier: @MainActor () -> SubscriptionTier

    /// The last context confirmed delivered, so an unchanged one is not handed
    /// over again. Every foreground asks, and almost none of them carry news.
    private var sent: WatchHandoff?

    /// The session order the wrist is owed, riding the next context out.
    ///
    /// In memory on purpose, unlike the erasure marker: an order matters for
    /// the minutes `WatchOrderLedger` keeps it fresh, and a relaunch that
    /// forgets it rebuilds the next context without it — which is exactly what
    /// scrubs a stale order out of the last-value-wins dictionary.
    private var order: WatchSessionOrder?

    /// - Parameter entitledTier: what the person may use, asked afresh at every
    ///   hand-over. Defaulted to free so a caller that has nothing to say about
    ///   a subscription — every test that is not about one — says the safe
    ///   thing rather than the convenient one.
    public init(
        identity: any UserIdentityStore,
        scores: any BoltScoreRecording,
        defaults: UserDefaults = .standard,
        entitledTier: @escaping @MainActor () -> SubscriptionTier = { .free }
    ) {
        self.identity = identity
        self.scores = scores
        self.defaults = defaults
        self.entitledTier = entitledTier
    }

    /// Forgets what the watch was told, and records *why* it is about to be told
    /// something different.
    ///
    /// The outbox holds no practice of its own. What it holds is a claim about
    /// another device, and after a deletion that claim is both stale and
    /// dangerous — the wrist has the erased person's identity, their best pause,
    /// and whatever they breathed on it that has not gone up yet.
    ///
    /// Stored as the id itself rather than as a flag, which is what makes it
    /// self-expiring: a later sign-in or sign-out mints another id, the stored
    /// one stops matching, and the contexts that follow are ordinary again with
    /// nothing to remember to clear. Reading it from the identity store rather
    /// than being handed it is what keeps the ordering honest — `AccountModel`
    /// mints before it erases, so the replacement is already in place here.
    public func erase() async {
        sent = nil

        guard let userId = identity.userId() else { return }
        defaults.set(userId.uuidString, forKey: Self.erasedKey)
    }

    /// Places `order` so the next hand-over carries it, and says whether it was
    /// taken. A second placement replaces the first — only the newest order
    /// survives, which is the coalescing rule the whole channel runs on.
    ///
    /// Refused below `SubscriptionTier.watchConnected`, and this is where that
    /// gate lives rather than at the two models that place orders: an order is
    /// the phone asking the wrist to do something, which is the whole of what
    /// the pairing sells, and a gate at each producer would be a gate to add
    /// again with the third. Breathing on the wrist by hand goes nowhere near
    /// here and stays free.
    ///
    /// The answer is returned rather than swallowed because both callers have
    /// something to say about it — one draws a locked sheet, the other quietly
    /// leaves the badge empty — and neither can ask the question itself.
    public func place(_ order: WatchSessionOrder) -> Bool {
        guard entitledTier() >= .watchConnected else { return false }

        self.order = order
        return true
    }

    /// Takes a concluded order back out of the context — delivered, declined
    /// or timed out, it is no longer news, and the next ordinary push should
    /// not carry it along. A mismatched id is a stale conclusion arriving
    /// after a newer placement, and must not withdraw the newer order.
    public func withdraw(_ orderId: UUID) {
        guard order?.id == orderId else { return }
        order = nil
    }

    /// Offers whatever is outstanding to `send`, and remembers it only if that
    /// returned without throwing — so a hand-over that failed is retried by the
    /// next foreground rather than recorded as delivered.
    ///
    /// `send` takes the radio and nothing else. Passing it in rather than
    /// returning the context and trusting the caller to report back is what puts
    /// the whole rule in one tested place: there is no call sequence a caller
    /// can get wrong.
    ///
    /// `send` is not called at all in two cases that look alike from outside and
    /// differ underneath: no identity has been minted yet — minting is lazy on
    /// first use, and a context with no id is one the watch would refuse anyway —
    /// or the watch already holds exactly this.
    public func handOver(_ send: (WatchHandoff) throws -> Void) async rethrows {
        guard let userId = identity.userId() else { return }

        let handoff = await WatchHandoff(
            userId: userId,
            sessionCredential: identity.sessionCredential(),
            boltBestSeconds: scores.personalBest(),
            erasesPriorHistory: defaults.string(forKey: Self.erasedKey) == userId.uuidString,
            order: order,
            entitledTier: entitledTier()
        )
        // A changed tier is therefore news like any other, and the same
        // comparison that suppresses the ordinary re-send is what carries a
        // purchase to the wrist without waiting for a relaunch.
        guard handoff != sent else { return }

        try send(handoff)
        sent = handoff
    }
}
