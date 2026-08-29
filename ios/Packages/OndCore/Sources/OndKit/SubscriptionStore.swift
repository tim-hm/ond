import Foundation
import os

/// Which tier this person is on, and the only thing any screen asks.
/// Offline-first: the tier is answered from `StoreKit` on this device, and the
/// server submission is a sync alongside, never a gate. This device decides
/// what to show; the server decides what to spend. A sync failure reaches no
/// view — the assistant answers from its rules until the next launch retries.
@MainActor
@Observable
public final class SubscriptionStore: PersonalStore {
    private static let logger = Logger(category: "subscription")

    /// The key keeps its old spelling on purpose: it names a value already
    /// written to disk on installed builds, and renaming it would silently drop
    /// every existing subscriber back to free for one launch.
    private static let tierKey = "plus.tier"

    /// What this person is entitled to right now. Written through to
    /// `UserDefaults` and read back at init, so a cold launch shows the right
    /// thing on the first frame instead of re-locking a subscriber's catalogue
    /// while `StoreKit` answers. The equality guard matters: `refresh` assigns
    /// unconditionally on every foreground, and `didSet` fires on equal values.
    public private(set) var tier: SubscriptionTier {
        didSet {
            guard oldValue != tier else { return }

            defaults.set(tier.rawValue, forKey: Self.tierKey)
        }
    }

    /// When the current paid entitlement ends after auto-renewal was disabled.
    ///
    /// Absent for free, renewing, or unverifiable renewal information. This is
    /// display metadata only: `tier` remains the sole feature gate.
    public private(set) var nonRenewingExpirationDate: Date?

    /// The two cadences on offer, monthly first, once the App Store has said
    /// what they cost.
    public private(set) var products: [SubscriptionProduct] = []

    /// How far a purchase or a restore has got. One enum rather than a pair of
    /// flags: two booleans admit four states, and "busy while awaiting
    /// approval" is not one of them.
    public enum PurchaseState: Sendable, Equatable {
        case idle
        /// A purchase or a restore is in flight, and no second one may start.
        case working
        /// The purchase went to Ask to Buy. The answer arrives later through
        /// `updates`, so this is where it rests rather than a step on the way
        /// back to `idle` — the buttons come back to life while somebody else
        /// decides.
        case awaitingApproval
        /// The App Store had no product under this build's ids: nothing to
        /// buy, nothing charged. A distinct case because it never clears
        /// itself — on a device the product is not approved in App Store
        /// Connect; in the simulator the run got no `StoreKit` configuration,
        /// which only `mise run ios:sim:phone` and Xcode's Run action supply.
        case unavailable
    }

    public private(set) var purchaseState: PurchaseState = .idle

    /// How far the last submission got — the only question the coach screen
    /// asks. The verifier's reason belongs in the log line at the catch,
    /// where it is already in hand.
    public enum SubmissionOutcome: Sendable, Equatable {
        /// Refused because this build's transactions are signed locally
        /// (see `SubscriptionTransaction.isLocallySigned`): a dev build
        /// working as designed.
        case refusedLocallySigned
        /// Refused an Apple-signed transaction: a purchase not being honoured.
        case refused
        /// Held by the server's transfer cooldown — a reinstall inside the
        /// 24-hour window, waiting for the purchase to move over by itself.
        /// Neither shade of refused, because the coach's notice must be able
        /// to say "wait a day" instead of "retry" or "contact support".
        case held
    }

    /// How the last submission fell short — refused, or held by the transfer
    /// cooldown — cleared by any submission the server accepts.
    public private(set) var lastSubmission: SubmissionOutcome?

    /// Whether a button should refuse to start anything, which is the only
    /// question the paywall asks of `purchaseState`. Deliberately false while an
    /// Ask to Buy is outstanding: that answer is somewhere else, and the buttons
    /// have no reason to stay dead waiting for it.
    public var isBusy: Bool {
        purchaseState == .working
    }

    /// Whether a purchase went to Ask to Buy, so the paywall says so rather than
    /// looking as though the button did nothing.
    public var isAwaitingApproval: Bool {
        purchaseState == .awaitingApproval
    }

    /// Whether this build has anything to sell, so the paywall can say that
    /// nothing was charged rather than leaving a pressed button unexplained.
    public var isUnavailable: Bool {
        purchaseState == .unavailable
    }

    private let front: any StoreFront
    private let entitlements: any EntitlementSyncing
    private let defaults: UserDefaults

    /// Transactions that reached a verdict the server will not change this
    /// launch. In memory on purpose — the retry policy is one submission per
    /// transaction per launch. Persisting it would cost the ability to ever
    /// re-sync: a server row lost or restored from a backup would never hear
    /// about the purchase again. The RPC is idempotent so resending is safe.
    private var settled: Set<String> = []

    private let refreshes = SubscriptionRefreshCoordinator()

    public init(
        front: any StoreFront,
        entitlements: any EntitlementSyncing,
        defaults: UserDefaults = .standard
    ) {
        self.front = front
        self.entitlements = entitlements
        self.defaults = defaults
        // Assigning in an initialiser does not run `didSet`, which is what keeps
        // this from writing back the value it just read.
        tier = SubscriptionTier.cached(in: defaults, forKey: Self.tierKey)
        nonRenewingExpirationDate = nil
    }

    /// Reads what `StoreKit` already knows, then keeps listening for the rest
    /// of the process's life. Does not return until the stream ends, so it
    /// belongs in a `.task`, not awaited on a path something else waits for.
    public func watch() async {
        await refresh()

        for await transaction in front.updates() {
            // Submitted directly rather than only through `refresh`, because a
            // revocation is the one thing that arrives here and is *absent*
            // from `currentEntitlements` — leaving it unsent would have the
            // server honour a refund until the subscription's original expiry.
            refreshes.record(transaction, tier: &tier, endingAt: &nonRenewingExpirationDate)
            await submit(transaction)
            await refresh()
        }
    }

    /// Re-reads the entitlement and pushes anything the server has not seen.
    /// Safe on every foreground: with nothing outstanding it is one local
    /// `StoreKit` read and no network. Deliberately does not fetch the prices —
    /// an App Store round trip only the paywall needs. The tier is the highest
    /// reported, because a crossgrade can leave both visible for a moment.
    public func refresh() async {
        await refreshes.run { await refreshEntitlements() }
    }

    private func refreshEntitlements() async {
        let reported = await front.currentEntitlements()
        let now = Date()
        let entitlements = refreshes.entitlements(byAddingUnconfirmedTo: reported, at: now)
        let active = entitlements.filter { $0.entitledTier(at: now) > .free }

        tier = active
            .map { $0.entitledTier(at: now) }
            .max() ?? .free
        nonRenewingExpirationDate = Self.nonRenewingExpirationDate(in: active)

        for transaction in entitlements {
            await submit(transaction)
        }
    }

    /// Fetches the prices, for a screen about to show them. Separate from
    /// [`refresh`]: folding in the one App Store fetch would put a network call
    /// on every cold launch for people who never open the paywall. Cached after
    /// the first success, so reopening the sheet is free.
    public func loadProducts() async {
        // Counted rather than emptiness-checked: the App Store can answer with
        // one of the two, and latching on that would leave the other cadence
        // priceless for the life of the process.
        guard products.count < SubscriptionPlan.allCases.count else { return }

        products = await front.products()
    }

    /// Buys `plan`. Both products share one subscription group, so buying one
    /// while holding the other is a change of plan Apple prorates, not a second
    /// subscription. The entitlement is applied from `StoreKit`'s answer, not
    /// the server's, so the screen changes the moment the sheet dismisses.
    public func purchase(_ plan: SubscriptionPlan) async {
        guard purchaseState != .working else { return }
        purchaseState = .working

        do {
            switch try await front.purchase(plan) {
            case let .purchased(transaction):
                refreshes.record(transaction, tier: &tier, endingAt: &nonRenewingExpirationDate)
                await submit(transaction)
                await refresh()
                purchaseState = .idle
            case .pending:
                purchaseState = .awaitingApproval
            case .cancelled:
                purchaseState = .idle
            }
        } catch StoreFrontError.productUnavailable {
            purchaseState = .unavailable
            // At `error`, unlike everything else this store logs: it is the one
            // failure that stays broken until somebody changes something, and
            // the pointer is what turns a dead button back into a minute's work.
            Self.logger
                .error(
                    """
                    nothing on sale: no product for \
                    \(plan.productIdentifier, privacy: .public). \
                    In the simulator, launch through `mise run ios:sim:phone` — a bare \
                    `simctl launch` applies no StoreKit configuration.
                    """
                )
        } catch {
            purchaseState = .idle
            // Not surfaced. What is left here is either the person's own
            // cancellation dressed differently or an App Store outage, and a
            // paywall that shows a technical error has already lost the sale it
            // was there for.
            Self.logger.notice("purchase failed: \(error.diagnostic, privacy: .public)")
        }
    }

    /// Restores an existing subscription, which App Review requires every
    /// paywall to offer.
    ///
    /// It prompts for an App Store password, so it runs only from a button.
    public func restore() async {
        guard purchaseState != .working else { return }
        // Restored to what it was rather than to idle: a restore run while an
        // Ask to Buy is still outstanding must not clear the notice that
        // explains why nothing has happened yet.
        let resting = purchaseState
        purchaseState = .working
        defer { purchaseState = resting }

        do {
            try await front.restore()
        } catch {
            Self.logger.notice("restore failed: \(error.diagnostic, privacy: .public)")
        }

        // Regardless of the outcome: `AppStore.sync()` throws when the person
        // dismisses the password prompt, and the entitlement may still have
        // arrived through `updates` while it was open.
        await refresh()
    }

    /// Drops the cached tier and re-derives it; it cancels nothing. Deleting an
    /// account does not end an App Store subscription — only Apple can — so the
    /// refresh puts back what the erasure took, instead of showing a paying
    /// subscriber the free tier. Clearing `settled` lets the refresh resubmit
    /// the transaction onto the new identity this run, which a merge relies on.
    public func erase() async {
        tier = .free
        nonRenewingExpirationDate = nil
        settled.removeAll()
        defaults.removeObject(forKey: Self.tierKey)

        await refresh()
    }

    /// Re-offers every current transaction to the server, for the one screen
    /// that knows the entitlement has not landed. Clearing the ledger is the
    /// point: `submit` runs once per transaction per launch, and a plain
    /// re-read would only confirm the state the retry is trying to leave.
    public func resubmit() async {
        settled.removeAll()
        await refresh()
    }

    /// Tells the server about one transaction, at most once per launch. A
    /// failure leaves the key unrecorded, so the next launch retries; a late
    /// purchase costs only a rule-based assistant meanwhile. A refusal settles
    /// the key — the same bytes would be refused again — and is logged at
    /// `error` when Apple-signed: a paying customer's purchase not honoured.
    private func submit(_ transaction: SubscriptionTransaction) async {
        guard !settled.contains(transaction.submissionKey) else { return }

        do {
            try await entitlements.submit(transaction.jws)
            settled.insert(transaction.submissionKey)
            lastSubmission = nil
        } catch let EntitlementRepositoryError.rejected(reason) {
            settled.insert(transaction.submissionKey)

            if transaction.isLocallySigned {
                lastSubmission = .refusedLocallySigned
                Self.logger.notice(
                    """
                    the server refused a locally signed transaction, as it must — \
                    a local StoreKit purchase never syncs. Reason: \
                    \(reason, privacy: .public)
                    """
                )
            } else {
                lastSubmission = .refused
                Self.logger.error(
                    """
                    the server refused an Apple-signed transaction — a real \
                    purchase is not being honoured and the money path needs \
                    looking at. Reason: \(reason, privacy: .public)
                    """
                )
            }
        } catch let EntitlementRepositoryError.held(reason) {
            // Deliberately not settled: the hold expires on its own, and the
            // next launch's resubmission is exactly what completes the
            // transfer. At notice, not error — the cooldown working is not the
            // money path needing attention.
            lastSubmission = .held
            Self.logger.notice(
                "entitlement held by the transfer cooldown: \(reason, privacy: .public)"
            )
        } catch {
            Self.logger
                .notice(
                    "entitlement sync deferred: \(error.diagnostic, privacy: .public)"
                )
        }
    }
}
