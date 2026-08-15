import OndKit
import SwiftUI

/// The composition root's factories: the small groups of dependencies that are
/// built together because a closure or a shared instance joins them, and that
/// nothing outside this root may construct.
///
/// Beside `OndApp` rather than in it so the root itself stays readable as what
/// it is — a list of what this install holds, and one `init` that fills it in.
extension OndApp {
    /// Whether this Debug launch belongs to the deterministic UI-test harness.
    static var isUiTesting: Bool {
        #if DEBUG
            ProcessInfo.processInfo.arguments.contains("--ui-testing")
        #else
            false
        #endif
    }

    /// Chooses the launch gate while allowing one UI test to exercise first run.
    static func firstRunGate(for records: FirstRunRecords) -> FirstRunGate? {
        #if DEBUG
            let showsFirstRun = ProcessInfo.processInfo.arguments
                .contains("--ui-testing-first-launch")
            return isUiTesting && !showsFirstRun ? nil : records.gate
        #else
            return records.gate
        #endif
    }

    /// The two records first run is gated on, and their verdict.
    ///
    /// Named rather than a tuple for `Coach`'s reason: three unlabelled members
    /// at a call site is a positional puzzle. The verdict travels with them
    /// because it is nothing but a reading of the two — keeping it here is what
    /// stops a caller holding the records and asking a *second* time, at a
    /// second moment, and getting a different answer.
    struct FirstRunRecords {
        let profiles: ProfileStore
        let consent: SafetyConsentStore
        /// What these two between them say is still outstanding.
        let gate: FirstRunGate?
    }

    /// The two records first-run is gated on: the onboarding answers and the
    /// safety consent. Built together because `FirstRunGate.pending` reads them
    /// together, and nothing else constructs either.
    /// One person's own exercises, over a cache.
    ///
    /// Cached for the reason the catalogue is, and it was the one list on the
    /// Exercises tab without a local copy: a phone that could not reach the
    /// server replaced somebody's own exercises with an error, beside a
    /// catalogue that kept drawing from its own snapshot.
    static func ownExercises(
        baseURL: URL,
        identity: any UserIdentityStore
    ) -> CachedUserTechniqueRepository {
        CachedUserTechniqueRepository(
            caching: UserTechniqueRepository(baseURL: baseURL, identity: identity),
            identity: identity
        )
    }

    static func firstRunRecords(
        baseURL: URL,
        identity: any UserIdentityStore
    ) -> FirstRunRecords {
        let profiles = ProfileStore(
            profiles: ProfileRepository(baseURL: baseURL, identity: identity)
        )
        let consent = SafetyConsentStore()

        return FirstRunRecords(
            profiles: profiles,
            consent: consent,
            gate: .pending(profiles: profiles, consent: consent)
        )
    }

    /// The first-run flow, for the launch that shows it and no other.
    ///
    /// A factory rather than an expression in the cover that presents it: that
    /// closure runs on every evaluation of the scene's body, and each model
    /// built in one is discarded immediately — `OnboardingView` keeps the first
    /// in `@State`. Cheap when the flow held three references; less so now that
    /// building one reads four preferences and snapshots them as the baseline
    /// it compares against.
    ///
    /// Nil for every launch after the first, so an install that has onboarded
    /// carries none of this for the process's life.
    static func onboarding(
        _ records: FirstRunRecords,
        schedules: ScheduleStore,
        catalogue: TechniqueListModel,
        settings: SessionSettings,
        coach: Coach
    ) -> OnboardingModel? {
        guard records.gate == .onboarding else { return nil }

        return OnboardingModel(
            store: records.profiles,
            schedules: schedules,
            catalogue: catalogue,
            consent: records.consent,
            // The two stores whose switches the flow collects, so that leaving
            // that step is what writes them — see
            // `OnboardingModel.applyOptIns()`.
            settings: settings,
            health: coach.heart,
            // The store rather than a snapshot of it: `plus.watch()` is still
            // resolving the entitlement while the welcome screen is up, and a
            // purchase made on the trial step moves it under the flow.
            plus: coach.plus
        )
    }

    /// Makes the one reminder the stored dial position implies, if first run
    /// has not already made it.
    ///
    /// The invariant is `ReminderDial.seedIfNeeded()`'s: a profile whose dial
    /// is off `never` has a schedule. Onboarding seeds at its own last step;
    /// the standalone safety terms are the other way first run ends, and
    /// without this somebody who quit the flow after the answers were stored
    /// keeps a profile that says "once a day" with no appointment behind it,
    /// permanently.
    ///
    /// Fire-and-forget, and after the terms rather than before them, so the
    /// notification prompt `ScheduleStore.add` raises lands over Home.
    @MainActor
    static func seedReminder(
        profiles: ProfileStore,
        schedules: ScheduleStore,
        catalogue: TechniqueListModel
    ) {
        let dial = ReminderDial(profiles: profiles, schedules: schedules, catalogue: catalogue)

        Task { await dial.seedIfNeeded() }
    }

    /// What somebody is entitled to, the heart-trends store, and the assistant
    /// that asks it — one factory, because they are one dependency chain.
    ///
    /// The subscription store is over the two seams it needs: the App Store
    /// itself, and this server's record of what that store has been told. The
    /// trends store reads it, because reading Health is what önd+ sells and the
    /// gate belongs on the thing that reads rather than at each caller. The
    /// assistant reads *that*, per request.
    ///
    /// Built together rather than separately because the order is load-bearing
    /// in one direction and the root has no other reason to know it. Each of the
    /// three is handed back, because the root holds all three for its own
    /// reasons: the deletion list, the Settings screen, and every guidance
    /// surface.
    static func coach(
        baseURL: URL,
        identity: any UserIdentityStore,
        health: HealthKitHealthStore
    ) -> Coach {
        let plus = SubscriptionStore(
            front: StoreKitStoreFront(),
            entitlements: EntitlementRepository(baseURL: baseURL, identity: identity)
        )
        // The tier through a closure, read at each Health read rather than
        // captured now, so a subscription that lapses stops the reads on the
        // next question rather than on the next launch.
        let heart = HealthContextModel(store: health, entitledTier: { plus.tier })
        let assistant = AssistantRepository(
            baseURL: baseURL,
            identity: identity,
            // Asked per request, so withdrawing the opt-in in Settings takes
            // effect on the very next question with no restart.
            healthContext: { await heart.context() }
        )
        return Coach(plus: plus, heart: heart, assistant: assistant)
    }

    /// The three [`coach(baseURL:identity:health:)`] hands back.
    ///
    /// Named rather than a tuple because three unlabelled members at a call site
    /// is a positional puzzle, and because the chain between them — the store
    /// gates the trends, the trends brief the assistant — is worth a type to
    /// hang the explanation on.
    struct Coach {
        let plus: SubscriptionStore
        let heart: HealthContextModel
        let assistant: any AssistantReading
    }

    /// The practice model shared by Home, Progress, and the sync queue.
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

    /// The channel to the wrist, and the outbox that decides what goes down it.
    ///
    /// Together because the link is built over the outbox and nothing else ever
    /// wants one without the other. The tier is read through a closure rather
    /// than captured as a value: it decides whether an order may be placed at
    /// all, and a value read once at launch would leave somebody who subscribed
    /// this morning unable to send a session to their watch until they
    /// relaunched.
    static func pairing(
        identity: any UserIdentityStore,
        scores: any BoltScoreRecording,
        plus: SubscriptionStore
    ) -> (WatchHandoffOutbox, WatchLink) {
        let outbox = WatchHandoffOutbox(
            identity: identity,
            scores: scores,
            entitledTier: { plus.tier }
        )
        return (outbox, WatchLink(outbox: outbox))
    }

    /// Everything the phone asks of the wrist: the model that sends a discreet
    /// occasion there, the one that borrows its sensor for a session here, and the
    /// link told where the wrist's answers go.
    ///
    /// Built together because they are joined in both directions and none can name
    /// the other at construction — the models send through the link's radio, and
    /// the link resolves the wrist's messages back onto them. Both orders ride the
    /// same outbox the identity does, deliberately: `applicationContext` is one
    /// dictionary, wholly replaced per write, so a second writer would clobber the
    /// handoff the watch depends on for everything else.
    static func wristHandoff(
        over outbox: WatchHandoffOutbox,
        through watch: WatchLink,
        answering journey: JourneyModel
    ) -> (WristLaunchModel, PulseMonitor) {
        // One launcher for both, because its "already asked for the workout
        // grant" flag is per-process dedupe — two would put a second Health
        // sheet in front of somebody who has already answered it. Its own type
        // rather than the Health store: it holds HealthKit for the workout
        // *runtime* and never touches a sample, which is the line
        // `HealthKitHealthStore`'s doc draws.
        let launcher = WristLauncher()
        // Weakly, so nothing here retains the link that retains it: the link
        // holds these models to route the wrist's answers, and all three live for
        // the process — a cycle that costs nothing today and leaks the first time
        // any of them is rebuilt.
        let push: @MainActor () -> Void = { [weak watch] in watch?.push() }

        let wrist = WristLaunchModel(outbox: outbox, launcher: launcher, push: push)
        let pulse = PulseMonitor(outbox: outbox, launcher: launcher, push: push)
        watch.route(launches: wrist, pulse: pulse, journey: journey)
        return (wrist, pulse)
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
