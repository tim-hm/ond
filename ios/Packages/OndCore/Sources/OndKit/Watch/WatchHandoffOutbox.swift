import Foundation

/// The phone's half of the pairing, minus the radio: what the watch is owed
/// and what it has already been told. Here rather than in the app target
/// because the deduplication is the point and its failure mode is silent — a
/// context never sent, or re-sent on every foreground — and the app target
/// has no test bundle. `WatchLink` keeps the `WCSession` calls and no more.
@MainActor
public final class WatchHandoffOutbox: PersonalStore {
    /// The identity a deletion minted, so the context that carries it can say
    /// what it replaced. On disk because the wrist may be unreachable for
    /// days and the phone relaunched in between — a flag that lived for the
    /// process would leave the watch holding an erased person's practice.
    private static let erasedKey = "watch.identityAfterDeletion"

    private let identity: any UserIdentityStore
    private let scores: any BoltScoreRecording
    private let defaults: UserDefaults

    /// What the person is entitled to, read afresh at each hand-over so a
    /// purchase made a moment ago is what the wrist is told. A closure rather
    /// than the `SubscriptionStore`: taking the store would put `StoreKit`'s
    /// surface behind a type whose tests have no App Store account.
    private let entitledTier: @MainActor () -> SubscriptionTier

    /// The terms version this person agreed to on this phone, read afresh at
    /// each hand-over for the same reason the tier is: somebody who agreed a
    /// minute ago must not have to relaunch before their wrist stops asking.
    /// A closure rather than the store, so a test can say what the phone has
    /// agreed to without keeping a consent record.
    private let agreedConsentVersion: @MainActor () -> Int?

    /// The last context confirmed delivered, so an unchanged one is not handed
    /// over again. Every foreground asks, and almost none of them carry news.
    private var sent: WatchHandoff?

    /// The session order the wrist is owed, riding the next context out. In
    /// memory on purpose: an order matters only while `WatchOrderLedger`
    /// keeps it fresh, and a relaunch that forgets it rebuilds the next
    /// context without it — scrubbing the stale order from the dictionary.
    private var order: WatchSessionOrder?

    /// - Parameter entitledTier: what the person may use, asked afresh at every
    ///   hand-over. Defaulted to free so a caller that has nothing to say about
    ///   a subscription — every test that is not about one — says the safe
    ///   thing rather than the convenient one.
    public init(
        identity: any UserIdentityStore,
        scores: any BoltScoreRecording,
        defaults: UserDefaults = .standard,
        entitledTier: @escaping @MainActor () -> SubscriptionTier = { .free },
        agreedConsentVersion: @escaping @MainActor () -> Int? = { nil }
    ) {
        self.identity = identity
        self.scores = scores
        self.defaults = defaults
        self.entitledTier = entitledTier
        self.agreedConsentVersion = agreedConsentVersion
    }

    /// Forgets what the watch was told and records why it is about to be told
    /// something different. Stored as the id itself rather than a flag, which
    /// makes it self-expiring: a later sign-in mints another id and the
    /// stored one stops matching. Read from the identity store because
    /// `AccountModel` mints before it erases, so the replacement is in place.
    public func erase() async {
        sent = nil

        guard let userId = identity.userId() else { return }
        defaults.set(userId.uuidString, forKey: Self.erasedKey)
    }

    /// Places `order` so the next hand-over carries it, and says whether it
    /// was taken. A second placement replaces the first — only the newest
    /// order survives, the channel's coalescing rule. Refused below
    /// `SubscriptionTier.watchConnected`; the gate lives here, once, rather
    /// than at every producer. Breathing on the wrist by hand stays free.
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

    /// Offers whatever is outstanding to `send`, and remembers it only if
    /// that returned without throwing — a failed hand-over is retried by the
    /// next foreground rather than recorded as delivered. `send` is not
    /// called while no identity has been minted (minting is lazy, and the
    /// watch refuses an id-less context) or the watch already holds this.
    public func handOver(_ send: (WatchHandoff) throws -> Void) async rethrows {
        guard let userId = identity.userId() else { return }

        let handoff = await WatchHandoff(
            userId: userId,
            sessionCredential: identity.sessionCredential(),
            boltBestSeconds: scores.personalBest(),
            erasesPriorHistory: defaults.string(forKey: Self.erasedKey) == userId.uuidString,
            order: order,
            agreedConsentVersion: agreedConsentVersion(),
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
