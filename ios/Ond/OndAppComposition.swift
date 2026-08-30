import OndKit
import SwiftUI

/// The composition root's factories: the groups of dependencies a closure or
/// a shared instance joins, which nothing outside this root may construct.
/// Beside `OndApp` rather than in it so the root stays readable as a list of
/// what this install holds.
extension OndApp {
    /// The two records first run is gated on, and their verdict. The verdict
    /// travels with them because it is only a reading of the two — kept here
    /// so a caller cannot ask again at a second moment and get a different
    /// answer.
    struct FirstRunRecords {
        let profiles: ProfileStore
        let consent: SafetyConsentStore
        /// What these two between them say is still outstanding.
        let gate: FirstRunGate?
    }

    /// One person's own exercises, over a cache: without one, a phone that
    /// could not reach the server replaced somebody's own exercises with an
    /// error, beside a catalogue that kept drawing from its own snapshot.
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

    /// The first-run flow, for the launch that shows it and no other. A
    /// factory, not an expression in the cover: that closure runs on every
    /// body evaluation, and building a model snapshots four preferences as
    /// the baseline it compares against. Nil after the first launch, so an
    /// onboarded install carries none of this for the process's life.
    static func onboarding(
        _ records: FirstRunRecords,
        schedules: ScheduleStore,
        catalogue: TechniqueListModel,
        settings: SessionSettings,
        coach: Coach
    ) -> OnboardingModel? {
        // Through `firstRunGate` rather than asking the records again: read
        // separately the two disagreed under the trial route, and a cover with
        // no model to draw falls through to Home.
        guard firstRunGate(for: records) == .onboarding else { return nil }

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
            plus: coach.plus,
            startingAt: onboardingStartStep
        )
    }

    /// Makes the one reminder the stored dial position implies, if first run
    /// has not already. Onboarding seeds at its own last step; without this
    /// the standalone-safety route leaves a profile saying "once a day" with
    /// no appointment behind it, permanently. Fire-and-forget, after the
    /// terms, so the notification prompt lands over Home.
    @MainActor
    static func seedReminder(
        profiles: ProfileStore,
        schedules: ScheduleStore,
        catalogue: TechniqueListModel
    ) {
        let dial = ReminderDial(profiles: profiles, schedules: schedules, catalogue: catalogue)

        Task { await dial.seedIfNeeded() }
    }

    /// The entitlement store, the heart-trends store, and the assistant — one
    /// factory because they are one chain: the trends store gates its Health
    /// reads on the tier (the gate belongs on the reader, not each caller),
    /// and the assistant reads the trends per request. All three come back
    /// because the root holds each for its own reasons.
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

    /// The three [`coach(baseURL:identity:health:)`] hands back. Named rather
    /// than a tuple: three unlabelled members is a positional puzzle, and the
    /// chain between them is worth a type to hang the explanation on.
    struct Coach {
        let plus: SubscriptionStore
        let heart: HealthContextModel
        let assistant: any AssistantReading
    }

    /// The practice model shared by Home, Progress, and the sync queue. Built
    /// and returned together: the queue is the model's sync and also a store
    /// a deletion has to empty, so the root needs both and nothing else does.
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
            // The watch and the restore each hold their own copy of the
            // identity; telling them here makes signing out and deleting fan
            // out exactly as signing in does. The refold rides inside
            // `syncAdoptedIdentity` unconditionally — a deletion empties the
            // stores without the restore changing anything.
            watch.push()
            await journey.syncAdoptedIdentity()
            // Server-side and scoped to the id, so a changed identity is a
            // different list — and unlike the journey's stores, there is nothing
            // local to reconcile, only a fetch to redo.
            await own.load()
        }
    }

    /// The channel to the wrist, and the outbox that decides what goes down
    /// it — never wanted separately. The tier and the agreed terms are read
    /// through closures, not captured: values read at launch would leave
    /// somebody who subscribed, or agreed, this morning waiting for a relaunch
    /// before their watch heard about it.
    static func pairing(
        identity: any UserIdentityStore,
        scores: any BoltScoreRecording,
        plus: SubscriptionStore,
        consent: SafetyConsentStore
    ) -> (WatchHandoffOutbox, WatchLink) {
        let outbox = WatchHandoffOutbox(
            identity: identity,
            scores: scores,
            entitledTier: { plus.tier },
            agreedConsentVersion: { consent.agreed?.version }
        )
        return (outbox, WatchLink(outbox: outbox))
    }

    /// Everything the phone asks of the wrist, built together: the models send
    /// through the link's radio and the link resolves answers back onto them,
    /// so none can name the other at construction. Both orders ride the
    /// identity's outbox: `applicationContext` is one dictionary, wholly
    /// replaced per write, so a second writer would clobber the handoff.
    static func wristHandoff(
        over outbox: WatchHandoffOutbox,
        through watch: WatchLink,
        answering journey: JourneyModel
    ) -> (WristLaunchModel, PulseMonitor) {
        // One launcher for both: its "already asked for the workout grant"
        // flag is per-process dedupe — two would show a second Health sheet.
        // Its own type, not the Health store: it holds HealthKit for the
        // workout runtime and never touches a sample.
        let launcher = WristLauncher()
        // Weakly, so nothing here retains the link that retains it: the link
        // holds these models to route the wrist's answers, and all three live for
        // the process — a cycle that costs nothing today and leaks the first time
        // any of them is rebuilt.
        let push: @MainActor () -> Void = { [weak watch] in watch?.push() }

        let wrist = WristLaunchModel(outbox: outbox, launcher: launcher, push: push)
        let pulse = PulseMonitor(
            outbox: outbox,
            launcher: launcher,
            push: push,
            rehearsing: rehearsesWrist
        )
        watch.route(launches: wrist, pulse: pulse, journey: journey)
        return (wrist, pulse)
    }

    /// Signing in, signing out, and deleting everything. The list is the
    /// caller's, deliberately: the root alone knows all of it, and a factory
    /// assembling it would be a second place for a store to go missing from.
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
