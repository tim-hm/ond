import OndKit
import SwiftUI

/// The composition root's factories: the small groups of dependencies that are
/// built together because a closure or a shared instance joins them, and that
/// nothing outside this root may construct.
///
/// Beside `OndApp` rather than in it so the root itself stays readable as what
/// it is — a list of what this install holds, and one `init` that fills it in.
extension OndApp {
    /// The two records first-run is gated on: the onboarding answers and the
    /// safety consent. Built together because `FirstRunGate.pending` reads them
    /// together, and nothing else constructs either.
    static func firstRunRecords(
        baseURL: URL,
        identity: any UserIdentityStore
    ) -> (ProfileStore, SafetyConsentStore) {
        (
            ProfileStore(profiles: ProfileRepository(baseURL: baseURL, identity: identity)),
            SafetyConsentStore()
        )
    }

    /// The heart-trends store and the assistant that asks it, built together
    /// because the closure is their only join: the root needs the store for the
    /// deletion list and the Settings toggle, the assistant for every guidance
    /// surface, and nothing else needs to know they are related.
    static func coach(
        baseURL: URL,
        identity: any UserIdentityStore,
        health: HealthKitHealthStore
    ) -> (HealthContextModel, any AssistantReading) {
        let heart = HealthContextModel(store: health)
        let assistant = AssistantRepository(
            baseURL: baseURL,
            identity: identity,
            // Asked per request, so withdrawing the opt-in in Settings takes
            // effect on the very next question with no restart.
            healthContext: { await heart.context() }
        )
        return (heart, assistant)
    }

    /// The journey tab's model and the queue that drains into it.
    ///
    /// Built together and returned together because they are one thing built
    /// twice over: the queue is the model's sync, and it is also one of the
    /// stores a deletion has to empty — so the composition root needs both, and
    /// nothing else needs either.
    static func journey(
        baseURL: URL,
        identity: any UserIdentityStore,
        sessions: FileSessionStore,
        scores: FileBoltScoreStore,
        rates: FileRestingRateStore
    ) -> (JourneyModel, SessionSyncQueue) {
        let journeys = JourneyRepository(baseURL: baseURL, identity: identity)
        let queue = SessionSyncQueue(
            sessions: sessions,
            scores: scores,
            rates: rates,
            journeys: journeys,
            tombstones: sessions
        )

        return (
            JourneyModel(
                sessions: sessions,
                scores: scores,
                rates: rates,
                journeys: journeys,
                queue: queue
            ),
            queue
        )
    }

    /// What every path that changes the identity has to do once it has.
    ///
    /// A function rather than a closure written inline because it is the same
    /// three steps for signing in, signing out and deleting — and because the
    /// reason each of them is there outgrew the argument list it was sitting in.
    static func identityChange(
        telling watch: WatchLink,
        and journey: JourneyModel,
        reloading own: UserTechniqueModel
    ) -> @MainActor () async -> Void {
        {
            // The two things that hold their own copy of the identity: the
            // watch, which was handed one and caches it, and the restore, which
            // has already walked the history of whoever this device used to be.
            // Both are told here rather than at the sign-in button, so signing
            // out and deleting fan out exactly as signing in does. The refold
            // rides inside `syncAdoptedIdentity` — unconditionally, since a
            // deletion empties the stores without the restore changing anything.
            watch.push()
            await journey.syncAdoptedIdentity()
            // Server-side and scoped to the id, so a changed identity is a
            // different list — and unlike the journey's stores, there is nothing
            // local to reconcile, only a fetch to redo.
            await own.load()
        }
    }

    /// The handoff pair: the model that sends a discreet occasion to the wrist,
    /// and the link told where the wrist's answers go.
    ///
    /// Built together because they are joined in both directions and neither can
    /// name the other at construction — the model sends through the link's radio,
    /// and the link resolves the wrist's ack onto the model. The order rides the
    /// same outbox the identity does, deliberately: `applicationContext` is one
    /// dictionary, wholly replaced per write, so a second writer would clobber
    /// the handoff the watch depends on for everything else.
    static func wristHandoff(
        over outbox: WatchHandoffOutbox,
        through watch: WatchLink,
        answering journey: JourneyModel
    ) -> WristLaunchModel {
        let wrist = WristLaunchModel(
            outbox: outbox,
            // The launcher is its own type, not the Health store: it holds
            // HealthKit for the workout *runtime* and never touches a sample,
            // which is the line `HealthKitHealthStore`'s doc draws.
            launcher: WristLauncher(),
            // Weakly, so the pair does not retain each other: the link holds this
            // model to route the wrist's ack back to it, and both live for the
            // process — a cycle that costs nothing today and leaks the first time
            // either is rebuilt.
            push: { [weak watch] in watch?.push() }
        )
        watch.route(launches: wrist, journey: journey)
        return wrist
    }

    /// Signing in, signing out, and deleting everything — over the whole list of
    /// what this install holds about the person.
    ///
    /// The list is the caller's, deliberately: the root is the only place that
    /// knows all of it, and a factory that assembled the list itself would be a
    /// second place for a store to go missing from.
    static func account(
        baseURL: URL,
        identity: any UserIdentityStore,
        emptying stores: [any PersonalStore],
        onIdentityChange: @escaping @MainActor () async -> Void
    ) -> AccountModel {
        AccountModel(
            identity: identity,
            accounts: AccountRepository(baseURL: baseURL, identity: identity),
            stores: stores,
            onIdentityChange: onIdentityChange
        )
    }
}
