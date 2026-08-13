import Foundation
@testable import OndKit
import os
import Testing

// The doubles the account-deletion suite drives its real stores through.
// Split from `AccountDeletionTests` because that file holds a suite whose
// assertions grow one line per store the app learns to erase, and a hundred
// lines of fakes above them is what put it against the file-length limit.
// `RecordingEntitlements` deliberately stayed behind: `SubscriptionTests` has a
// private double of the same name, and an internal one here would shadow
// confusingly rather than collide honestly.

/// A server that erases on demand, or refuses to.
///
/// Only the deletion is modelled: `signIn` is unreachable from every test here
/// and pinned in `AccountModelTests` besides.
final class ErasingAccounts: AccountSyncing {
    /// What each erasure that reached the server presented, in order — nil for
    /// the anonymous case, which is what most of this suite drives.
    private let state = OSAllocatedUnfairLock<[String?]>(initialState: [])
    private let failure: (any Error)?

    init(failingWith failure: (any Error)? = nil) {
        self.failure = failure
    }

    /// How many erasures actually reached the server.
    var deletions: Int {
        state.withLock { $0.count }
    }

    /// The credentials those erasures carried, which is the only way to see
    /// whether the model forwarded what it was handed.
    var presentedTokens: [String?] {
        state.withLock { $0 }
    }

    func signIn(identityToken _: String) async throws -> SignedInIdentity {
        throw AccountRepositoryError.transport("not what this suite is about")
    }

    /// Unreachable from this suite, like the sign-in above: what a sign-out
    /// revokes is `AccountModelTests`'.
    func signOut() async throws {
        throw AccountRepositoryError.transport("not what this suite is about")
    }

    func delete(identityToken: String?) async throws {
        if let failure {
            throw failure
        }

        state.withLock { $0.append(identityToken) }
    }
}

/// A profile server that holds nothing and accepts everything, so the store
/// under test behaves exactly as it does on a device that has been online.
struct SettledProfiles: ProfileSyncing {
    func fetch() async throws -> Profile {
        .unanswered
    }

    @discardableResult
    func update(_ profile: Profile) async throws -> Profile {
        profile
    }
}

/// `StoreKit` with one live subscription on it, which is the state that makes
/// the interesting assertion possible: the account goes, the subscription does
/// not.
struct SubscribedStoreFront: StoreFront {
    func products() async -> [SubscriptionProduct] {
        []
    }

    func currentEntitlements() async -> [SubscriptionTransaction] {
        [
            SubscriptionTransaction(
                id: 1,
                productID: SubscriptionPlan.yearly.productIdentifier,
                expirationDate: .distantFuture,
                revocationDate: nil,
                jws: "jws-plus"
            ),
        ]
    }

    func updates() -> AsyncStream<SubscriptionTransaction> {
        AsyncStream { $0.finish() }
    }

    func purchase(_: SubscriptionPlan) async throws -> PurchaseOutcome {
        .cancelled
    }

    func restore() async throws {}
}

/// Records every list the store re-synced it with, which is how a test sees the
/// pending notification requests being taken back — an empty sync is what
/// removes them.
final class RecordingNotifier: ScheduleNotifying {
    private let state = OSAllocatedUnfairLock(initialState: [[Schedule]]())

    var synced: [[Schedule]] {
        state.withLock { $0 }
    }

    func requestAuthorization() async -> Bool {
        true
    }

    func sync(_ schedules: [Schedule]) async {
        state.withLock { $0.append(schedules) }
    }
}

/// Health that has nothing to say, because none of this is about what it holds —
/// the model stores exactly one thing, and it is the person's own choice.
struct SilentHealthStore: HealthStore {
    func requestReadAuthorization() async {}

    func restingHeartRate(from _: Date, to _: Date) async -> [DailyQuantity] {
        []
    }

    func heartRateVariability(from _: Date, to _: Date) async -> [DailyQuantity] {
        []
    }

    func respiratoryRate(from _: Date, to _: Date) async -> [DailyQuantity] {
        []
    }

    func writeMindfulSession(from _: Date, to _: Date) async {}

    func writeMood(_: Mood, at _: Date) async {}
}

/// A Keychain that cannot be reached: reads answer nothing, writes fail.
///
/// `KeychainUserIdentityStore.userId()` mints on an empty store, so emptiness
/// alone (`FakeStorage(holding: nil)`) still produces an id — this is the only
/// way a test puts the model in the `userId == nil` state that a real unreadable
/// Keychain causes.
struct UnreachableStorage: IdentityStorage {
    func read() -> UUID? {
        nil
    }

    func insert(_: UUID) -> UUID? {
        nil
    }

    func replace(with _: UUID) -> Bool {
        false
    }
}

/// The journey's local world: the three files a practice lives in, over one
/// directory, and the queue that drains them.
///
/// Grouped rather than four properties on the install because they are built
/// together, erased together, and grew together — the second measurement is
/// what took `AccountDeletionTests.install()` past `function_body_length`.
@MainActor
struct JourneyStores {
    let sessions: FileSessionStore
    let scores: FileBoltScoreStore
    let rates: FileRestingRateStore
    let queue: SessionSyncQueue

    /// - Parameter defaults: where the sync ledger lives, shared with the rest
    ///   of the install so that one suite holds everything a deletion empties.
    init(in directory: URL, defaults: UserDefaults) {
        sessions = FileSessionStore(directory: directory)
        scores = FileBoltScoreStore(directory: directory)
        rates = FileRestingRateStore(directory: directory)
        queue = SessionSyncQueue(
            sessions: sessions,
            scores: scores,
            rates: rates,
            journeys: ServerSpy(),
            tombstones: sessions,
            ledger: SyncLedger(defaults: defaults)
        )
    }

    /// In the order the composition root writes them, which is the order this
    /// suite exists to keep honest.
    var erasable: [any PersonalStore] {
        [sessions, scores, rates, queue]
    }
}
