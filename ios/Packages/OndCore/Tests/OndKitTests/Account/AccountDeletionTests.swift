import Foundation
@testable import OndKit
import os
import Testing

/// Records the transactions the client pushes, which is how a test sees the
/// entitlement being re-claimed under the identity that replaced the erased one.
private final class RecordingEntitlements: EntitlementSyncing {
    private let state = OSAllocatedUnfairLock(initialState: 0)

    var submissions: Int {
        state.withLock { $0 }
    }

    func submit(_: String) async throws {
        state.withLock { $0 += 1 }
    }
}

/// Everything a deletion has to reach, wired the way the composition root
/// wires it.
@MainActor
private struct DeletionInstall {
    let identity: KeychainUserIdentityStore
    let accounts: ErasingAccounts
    let journey: JourneyStores
    let profiles: ProfileStore
    let consent: SafetyConsentStore
    let schedules: ScheduleStore
    let notifier: RecordingNotifier
    let plus: SubscriptionStore
    let entitlements: RecordingEntitlements
    let health: HealthContextModel
    let outbox: WatchHandoffOutbox
    let defaults: UserDefaults
    let account: AccountModel
    let told: OSAllocatedUnfairLock<Int>
}

/// Deleting an account, over the real stores rather than spies of them. The
/// local half has no cascade: two files, half a dozen `UserDefaults` keys and
/// their in-memory copies all have to be emptied by name, and a spy would
/// prove only that `AccountModel` called something. Driven through the same
/// seams `AccountModelTests` uses, so this runs on the host, no simulator.
@MainActor
@Suite("Deleting an account")
struct AccountDeletionTests {
    private func install(
        accounts: ErasingAccounts = ErasingAccounts(),
        storage: any IdentityStorage = FakeStorage(holding: anIdentity())
    ) throws -> DeletionInstall {
        let directory = URL.temporaryDirectory.appending(path: "ond-deletion-\(UUID().uuidString)")
        let defaults = try #require(UserDefaults(suiteName: "deletion-\(UUID().uuidString)"))

        let identity = KeychainUserIdentityStore(storage: storage)
        let journey = JourneyStores(in: directory, defaults: defaults)
        let profiles = ProfileStore(profiles: SettledProfiles(), defaults: defaults)
        let consent = SafetyConsentStore(defaults: defaults)
        let notifier = RecordingNotifier()
        let schedules = ScheduleStore(notifier: notifier, defaults: defaults)
        let entitlements = RecordingEntitlements()
        let plus = SubscriptionStore(
            front: SubscribedStoreFront(),
            entitlements: entitlements,
            defaults: defaults
        )
        let health = HealthContextModel(store: SilentHealthStore(), defaults: defaults)
        let outbox = WatchHandoffOutbox(
            identity: identity,
            scores: journey.scores,
            defaults: defaults
        )
        let account = accountModel(
            identity: identity,
            accounts: accounts,
            stores: journey.erasable + [profiles, consent, schedules, plus, health, outbox],
            defaults: defaults
        )

        return DeletionInstall(
            identity: identity,
            accounts: accounts,
            journey: journey,
            profiles: profiles,
            consent: consent,
            schedules: schedules,
            notifier: notifier,
            plus: plus,
            entitlements: entitlements,
            health: health,
            outbox: outbox,
            defaults: defaults,
            account: account.model,
            told: account.told
        )
    }

    /// The model under test, and the counter its identity-change hook bumps. Its own
    /// function because the store list is what this suite is really about: `OndApp`
    /// writes the same one out by hand, and a store missing from either copy is the bug
    /// these tests exist to catch. The counter comes back with the model because
    /// nothing else makes it and nothing else raises it.
    private func accountModel(
        identity: KeychainUserIdentityStore,
        accounts: ErasingAccounts,
        stores: [any PersonalStore],
        defaults: UserDefaults
    ) -> (model: AccountModel, told: OSAllocatedUnfairLock<Int>) {
        let told = OSAllocatedUnfairLock(initialState: 0)
        let model = AccountModel(
            identity: identity,
            accounts: accounts,
            stores: stores,
            defaults: defaults
        ) {
            told.withLock { $0 += 1 }
        }

        return (model, told)
    }

    /// A person who has used the app: onboarded, breathed twice, deleted one of
    /// those sessions, taken a controlled-pause test, opted the coach into their
    /// watch trends, set a standing weekday appointment, and synced.
    private func givenAPractice(on install: DeletionInstall) async {
        install.profiles.complete(
            with: Profile(
                goals: [],
                experienceLevel: .new,
                reminderIntensity: .never,
                intentNote: "to sleep"
            )
        )
        install.consent.record()
        // What an install upgraded from the version before the consent screen
        // still carries: `SafetyNoteStore`'s key, naming the contraindicated
        // exercises this person had been reading about.
        install.defaults.set(["wim-hof-rounds"], forKey: "safety.dismissedNotes")
        install.health.coachReadsHealthTrends = true
        install.schedules.add(
            Schedule(
                techniqueSlug: "box-breathing",
                techniqueName: "Box Breathing",
                hour: 8,
                minute: 0,
                weekdays: Weekday.weekdays
            )
        )

        let kept = SessionRecord(
            techniqueSlug: "box-breathing",
            startedAt: Date(timeIntervalSince1970: 1_700_000_000),
            duration: .milliseconds(120_000),
            cyclesCompleted: 8,
            breathCount: 8,
            completed: true
        )
        let deleted = SessionRecord(
            techniqueSlug: "physiological-sigh",
            startedAt: Date(timeIntervalSince1970: 1_700_000_100),
            duration: .milliseconds(60000),
            cyclesCompleted: 4,
            breathCount: 4,
            completed: true
        )
        await install.journey.sessions.record(kept)
        await install.journey.sessions.record(deleted)
        await install.journey.scores.record(BoltScore(seconds: 41))
        await install.journey.rates.record(RestingRate(breathsPerMinute: 13))

        // Fills the ledger, which is the one store that only exists once
        // something has actually been sent.
        await install.journey.queue.sync()
        await install.journey.sessions.remove(deleted.id)
    }

    /// The three files a practice lives in, and the tombstones beside them.
    ///
    /// Separated from the assertions below because they are the ones that grow:
    /// every measurement the app learns to take is another file here, and the
    /// test that reads them should not have to grow a line at the same time.
    private func expectTheFilesAreEmpty(on install: DeletionInstall) async {
        #expect(await install.journey.sessions.recordedSessions().isEmpty)
        #expect(
            await install.journey.sessions.tombstonedSessions().isEmpty,
            "a deletion in flight is a subset of this one"
        )
        #expect(await install.journey.scores.recordedScores().isEmpty)
        #expect(await install.journey.rates.recordedRates().isEmpty)
    }

    /// The whole of it, asserted store by store rather than through a spy. The subscription
    /// is the assertion that is *not* about erasure, and it is the one the confirmation
    /// copy promises: deleting an account cannot cancel an App Store subscription, so the
    /// tier has to come back from `StoreKit` rather than be left cleared — otherwise the
    /// app has appeared to cancel something it has no power over.
    @Test("Everything this device held is emptied, under an identity nobody has seen")
    func erasesEveryLocalStore() async throws {
        let install = try install()
        let before = install.identity.userId()
        await givenAPractice(on: install)

        await install.account.deleteAccount(identityToken: nil)

        #expect(install.accounts.deletions == 1)

        await expectTheFilesAreEmpty(on: install)

        #expect(install.profiles.profile == .unanswered)
        #expect(install.profiles.hasCompletedOnboarding == false)
        #expect(install.health.coachReadsHealthTrends == false)
        #expect(install.schedules.schedules.isEmpty)
        #expect(
            install.notifier.synced.contains([]),
            "a schedule left registered would buzz the erased account onto the lock screen"
        )
        #expect(
            install.defaults.stringArray(forKey: "journey.acknowledgedSessions") == nil,
            "the ledger answered for an identity that no longer exists"
        )
        #expect(
            install.defaults.object(forKey: "profile.answers") == nil,
            "an empty profile encoded into the defaults is still a record of somebody"
        )

        // The one store here that holds a dated statement rather than a
        // practice. Left behind, it would be the app keeping the single record
        // designed to outlast a memory, about somebody who asked to be
        // forgotten — and the terms are what onboarding asks again for.
        #expect(install.consent.agreed == nil)
        #expect(install.consent.needsConsent)
        #expect(
            install.defaults.object(forKey: "safety.consent") == nil,
            "a consent record surviving `delete everything` is the one it must not"
        )
        #expect(
            install.defaults.object(forKey: "safety.dismissedNotes") == nil,
            "the retired dismissal key still named the exercises this person read about"
        )

        #expect(install.identity.userId() != nil)
        #expect(install.identity.userId() != before, "one request on the old id resurrects it")
        #expect(install.account.state == .localOnly)
        #expect(install.account.progress == .idle)
        #expect(install.told.withLock { $0 } == 1, "the watch and the journey both hold a copy")

        #expect(
            install.plus.tier == .plus,
            "the subscription is Apple's to cancel, and the confirmation says so"
        )
        #expect(
            install.entitlements.submissions == 1,
            "the erased row took the App Store binding with it, so it is claimed again"
        )
    }

    /// A fact about what stays on screen rather than what was emptied: Settings
    /// keeps drawing the identifier row after a deletion, and the id it drew a
    /// moment ago now names nothing. It is the number somebody quotes to be
    /// found, so a stale one is a support request about a record that cannot
    /// exist.
    @Test("The identifier on offer is the one that replaced the erased account")
    func publishesTheReplacementIdentity() async throws {
        let install = try install()
        let before = install.account.userId

        await install.account.deleteAccount(identityToken: nil)

        #expect(install.account.userId == install.identity.userId())
        #expect(install.account.userId != before)
    }

    /// The order that makes a failed deletion survivable. Nothing local is
    /// touched until the server has actually erased the row, so somebody on a
    /// train is left with an app they can ask again from — rather than an empty
    /// one and a server that still holds everything.
    @Test("A deletion the server refused leaves the device exactly as it was")
    func keepsEverythingWhenTheServerCannotBeReached() async throws {
        let install = try install(
            accounts: ErasingAccounts(failingWith: AccountRepositoryError
                .transport(.stub("no route")))
        )
        let before = install.identity.userId()
        await givenAPractice(on: install)

        await install.account.deleteAccount(identityToken: nil)

        let sessions = await install.journey.sessions.recordedSessions()
        #expect(sessions.count == 1)
        #expect(install.profiles.hasCompletedOnboarding)
        #expect(
            !install.consent.needsConsent,
            "an unreachable server is no reason to make somebody agree to the terms again"
        )
        #expect(install.schedules.schedules.count == 1)
        #expect(install.identity.userId() == before)
        #expect(install.account.progress.reason != nil)
        #expect(install.told.withLock { $0 } == 0)
    }

    /// The wrist's half, from the phone's side: the context the watch is next handed
    /// has to name the fresh identity, carry no personal best, and say that what it
    /// replaces was deleted rather than merely renamed. All three come out of the
    /// ordering in `deleteAccount` — mint, then empty, then tell — and any other
    /// order produces a context that looks ordinary.
    @Test("The next context tells the watch there is nothing left to hold")
    func handsTheWatchAnErasure() async throws {
        let install = try install()
        await givenAPractice(on: install)

        await install.account.deleteAccount(identityToken: nil)

        var handed: WatchHandoff?
        await install.outbox.handOver { handed = $0 }
        let handoff = try #require(handed)

        #expect(handoff.userId == install.identity.userId())
        #expect(handoff.boltBestSeconds == nil)
        #expect(handoff.erasesPriorHistory)
    }

    /// A refusal for want of a credential repairs the state that caused it.
    /// `state` lives in `UserDefaults`, which a reinstall wipes; the Keychain
    /// identity and its Apple binding survive. Without the repair the refusal
    /// repeats forever and in-app deletion — the one thing Guideline 5.1.1(v)
    /// requires — is unreachable. `signIn` repairs the same state the other way.
    @Test("A deletion refused for want of a credential learns that this install is signed in")
    func learnsItIsSignedInFromARefusal() async throws {
        let install = try install(
            accounts: ErasingAccounts(
                failingWith: AccountRepositoryError.rejected("a fresh Apple credential is required")
            )
        )
        #expect(install.account.state == .localOnly)

        await install.account.deleteAccount(identityToken: nil)

        #expect(install.account.state == .signedIn)
        #expect(install.account.progress.reason != nil)
    }

    /// A refusal teaches nothing to an install that presented no identity. An
    /// unreachable Keychain sends no `ond-user-id`, and the server refuses that
    /// with the same status as a missing credential. That install is broken, not
    /// signed in — relabelling it would persist a false "Signed in with Apple"
    /// that puts an unhelpful Apple sheet in front of every retry.
    @Test("A refusal with no identity in hand does not relabel the install as signed in")
    func aRefusalWithoutAnIdentityTeachesNothing() async throws {
        let install = try install(
            accounts: ErasingAccounts(
                failingWith: AccountRepositoryError.rejected("no identity arrived")
            ),
            storage: UnreachableStorage()
        )
        #expect(install.account.userId == nil)

        await install.account.deleteAccount(identityToken: nil)

        #expect(install.account.state == .localOnly)
        #expect(install.account.progress.reason != nil)
    }

    /// The credential an Apple-bound erasure has to carry reaches the server. A
    /// bound identity that presents nothing is refused — deletion is the one
    /// irreversible operation, and the anonymous id alone is not a claim it acts
    /// on — so dropping the token would leave every signed-in person unable to
    /// erase. The anonymous case sends nil and is asked for nothing.
    @Test("A signed-in deletion presents the Apple credential it was handed")
    func presentsTheAppleCredential() async throws {
        let install = try install()

        await install.account.deleteAccount(identityToken: "jws-apple")

        #expect(install.accounts.presentedTokens == ["jws-apple"])
    }
}
