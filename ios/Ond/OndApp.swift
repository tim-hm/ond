import OndKit
import OndUI
import SwiftUI

@main
struct OndApp: App {
    /// This install's anonymous id, minted on first use and read from the
    /// Keychain thereafter. Handed to every repository, so one person is one
    /// identity across the whole app — and one *store*, so a sign-in that swaps
    /// the id is not left racing a second cache. See `LiveIdentity`.
    private let identity: any UserIdentityStore = LiveIdentity.store

    /// One store for the whole app: every session ends up in the same file, and
    /// the journey's sync has one place to drain. Concrete rather than `any
    /// SessionRecording`, because the sync queue also needs its other face —
    /// the tombstones deletions wait in until the server confirms them.
    private let sessions = FileSessionStore()

    /// What the screens record through: the same file, with each kept session
    /// also credited to Health as Mindful Minutes. The journey's sync below
    /// keeps the bare store — history restored from the server is not new
    /// practice, and must never write to Health again.
    private let recorder: any SessionRecording

    /// Controlled-pause scores, kept beside the sessions and for the same
    /// reason — Coach reads them with no network at all. Concrete for
    /// the reason the sessions are: a deletion has to be able to empty it.
    private let scores = FileBoltScoreStore()

    /// Resting rates, beside the pauses and on the same terms. The second
    /// check-in, and the second store a deletion has to empty.
    private let rates = FileRestingRateStore()

    /// The coach conversations, on this device only — the server keeps no
    /// transcript. Concrete for the reason the sessions are: a deletion has to
    /// be able to empty it.
    private let chats = FileConversationStore()

    /// Hands the identity above to the watch app, which never mints one of its
    /// own. Composed here because the pairing belongs to the install rather
    /// than to any screen, and because this is where the identity already is.
    private let watch: WatchLink

    /// Sends a discreet occasion to the wrist and waits out its answer. In the
    /// environment because home is where the tap happens and the link that
    /// carries the ack is here — the two ends of one exchange, composed
    /// together so nothing between them has to know it exists.
    ///
    /// A plain `let` beside the link it is wired to, not `@State`: the two are a
    /// pair joined in both directions, and `@State` would keep the first model
    /// while `route` had pointed the rebuilt link at a second — acks would then
    /// answer a model nothing reads, and every handoff would spin out its ten
    /// seconds and report failure. `@Observable` makes the environment read
    /// tracked whichever way it is held; `router` above has the same note.
    private let wrist: WristLaunchModel

    /// Borrows the wrist's sensor for a session running here, so the screen can
    /// show a live heart rate. Beside `wrist` because it is the same arrangement
    /// pointed the other way — an order out, an answer back — and a plain `let`
    /// for the same reason: the link routes the wrist's readings onto it.
    private let pulse: PulseMonitor

    /// The one connection to the health daemon this app opens, shared by
    /// everything that reads or writes Health data: the recorder that credits
    /// Mindful Minutes and the assistant's heart context. One instance because
    /// its "already asked for the write grant" and "already logged a refusal"
    /// flags are per-process dedupe — three stores would ask three times and log
    /// three refusals for the one standing state.
    private let health = HealthKitHealthStore()

    /// Where a mood tapped before or after a session goes. Over the same store
    /// as everything else here, and holding nothing itself — see `MoodRecorder`,
    /// which is a way out to Health rather than a place a feeling is kept.
    private let mood: MoodRecorder

    /// Where a tapped notification's request waits until there is a screen to
    /// answer it.
    ///
    /// A plain `let` rather than `@State`, like the rest of what is composed
    /// here and outlives every screen: the scene reads it through `AppChrome`,
    /// and `@Observable` is what makes that a tracked read whichever way it is
    /// held.
    private let router = NotificationRouter()

    /// Held for its lifetime and read by nothing: `UNUserNotificationCenter`
    /// keeps only a weak reference to its delegate, so the property is what
    /// stops a tapped reminder arriving at a deallocated object.
    private let notifications: NotificationDelegate

    /// In the environment rather than passed down, because the cue picker on the
    /// detail screen and the session that reads the setting are not adjacent.
    /// Built in `init` rather than here so the deletion list below can name the
    /// same instance the app reads.
    @State private var settings: SessionSettings

    /// Whether this person has önd+. In the environment for the same
    /// reason `settings` is: the surfaces that offer a subscription — the
    /// assistant's two strips, and the paywall they open — are nowhere near
    /// here, and threading a parameter through every screen between would touch
    /// every one of them.
    @State private var plus: SubscriptionStore

    /// Whether the safety terms have been agreed to, and the record of it. Held
    /// here rather than passed into onboarding alone because it is also what
    /// decides whether somebody who onboarded before that step existed is asked
    /// on this launch.
    @State private var consent: SafetyConsentStore

    /// The per-technique warnings — which of the two contraindicated exercises'
    /// notes this person has accepted, and whether they asked for them to stay
    /// away. In the environment because the session screen that shows them can
    /// be covered over any tab; composed here so the deletion list below can
    /// empty it.
    @State private var warnings: TechniqueWarningStore

    /// The cards this person starred on home, so they lead whatever the hour
    /// suggests. Composed here rather than beside home for the reason `warnings` is:
    /// the deletion list below has to be able to empty it, and this is the only place
    /// that knows the whole of that list.
    @State private var stars: StarredStopStore

    /// The heart-trends opt-in and the summary it unlocks, shared between the
    /// Settings toggle that flips it and the assistant that asks it per
    /// request. Constructed here — not file-scoped beside the assistant — so
    /// the one store holding something personal is built in sight of the
    /// deletion list below that has to empty it.
    @State private var heart: HealthContextModel

    /// The assistant's repository, built once for the whole app so every
    /// guidance surface shares one composition — and built *here* because its
    /// health context is the store above, which nothing outside this root may
    /// construct. `@State` like that store, not a plain `let`: the two are a
    /// pair joined by a captured reference, and if SwiftUI ever rebuilds the
    /// `App` value, `@State` is what discards the fresh pair together instead
    /// of splitting the kept store from a remade assistant reading a copy.
    @State private var assistant: any AssistantReading

    /// Holds the onboarding answers and knows whether they have been given.
    @State private var profiles: ProfileStore

    /// Signing in with Apple, signing out, and staying local-only. In the
    /// environment because the rows that offer it are in Settings, two pushes
    /// below a tab root that has no use for it.
    @State private var account: AccountModel

    /// What this install still owes before anybody breathes, decided once at
    /// launch and cleared when it is met.
    ///
    /// One piece of state for both covers rather than a flag each. They are
    /// mutually exclusive — a new install meets the safety terms as a step of
    /// onboarding, so it is never asked twice — and an enum is what makes that
    /// true rather than merely intended. Separate from
    /// `profiles.hasCompletedOnboarding`, which is set the moment the last
    /// answer is stored: a screen that dismissed itself on that flag would
    /// vanish before the person saw the last card.
    @State private var firstRun: FirstRunGate?

    /// The first-run flow itself, built here rather than inside the cover that
    /// presents it.
    ///
    /// A `fullScreenCover`'s content closure runs on every evaluation of this
    /// body, and a model constructed in one is a fresh model each time —
    /// discarded immediately, because `OnboardingView` holds the first in
    /// `@State`. Harmless while it was three stored references; less so now
    /// that building one reads four preferences out of `UserDefaults` and
    /// snapshots them as the baseline the flow compares against.
    ///
    /// Nil on every launch but the first, which is what stops an install that
    /// has onboarded from carrying the flow's dependencies for the process's
    /// life.
    @State private var onboarding: OnboardingModel?

    /// The catalogue, the foundations and the occasions, shared by every tab:
    /// home's dial and the techniques list are two views onto the same load.
    /// Built here, at the composition root, so a preview or a test can
    /// substitute the reading behind all three without touching the network.
    @State private var reference: Reference

    /// The exercises this person wrote for themselves. Its own model rather
    /// than part of the catalogue's: they come from a different service, they
    /// need the identity, and they are written as well as read.
    @State private var own: UserTechniqueModel

    /// The standing appointments, backed by local notifications. Composed in
    /// `init` rather than inline so the deletion below can reach it — the
    /// pending requests are iOS's rather than this app's, and nothing else can
    /// take them back. It outlives the Settings screen that edits it either way,
    /// because the notifications have to stay honest whether or not it is ever
    /// opened.
    @State private var schedules: ScheduleStore

    /// Totals, streaks, and the boards. Local-first: everything it shows about
    /// this person is folded from the three stores above, so the tab is complete
    /// before the sync it starts has finished.
    @State private var journey: JourneyModel

    /// Watched so the watch's copy of the identity and the personal best is
    /// refreshed on every foreground, rather than only on the launch that built
    /// this scene.
    @Environment(\.scenePhase) private var scenePhase

    init() {
        // First, so the display face resolves before any scene draws the
        // wordmark. Registration is idempotent; this call is about ordering.
        Theme.Typeface.register()

        let identity = identity
        let baseURL = AppConfiguration.apiBaseURL
        recorder = MindfulMinutesRecorder(wrapping: sessions, health: health)
        mood = MoodRecorder(store: health)

        // Ahead of the outbox, which reads the tier at every hand-over so the
        // wrist knows what it may do with this phone. Nothing else here needs
        // it this early; the ordering is the dependency.
        let coach = Self.coach(baseURL: baseURL, identity: identity, health: health)
        _plus = State(wrappedValue: coach.plus)
        _heart = State(wrappedValue: coach.heart)
        _assistant = State(wrappedValue: coach.assistant)

        let (outbox, watch) = Self.pairing(identity: identity, scores: scores, plus: coach.plus)
        self.watch = watch

        let schedules = ScheduleStore(notifier: NotificationScheduler())
        _schedules = State(wrappedValue: schedules)

        notifications = NotificationDelegate.installed(routing: router)

        let reference = Reference(baseURL: baseURL, identity: identity)
        _reference = State(wrappedValue: reference)

        let own = UserTechniqueModel(store: Self.ownExercises(baseURL: baseURL, identity: identity))
        _own = State(wrappedValue: own)

        let records = Self.firstRunRecords(baseURL: baseURL, identity: identity)
        _profiles = State(wrappedValue: records.profiles)
        _consent = State(wrappedValue: records.consent)
        _firstRun = State(wrappedValue: Self.firstRunGate(for: records))

        // The three stores composed from nothing at all. Together on one line
        // only because each is a local the deletion list below has to name,
        // which is all they have in common.
        let (warnings, stars, settings) =
            (TechniqueWarningStore(), StarredStopStore(), SessionSettings())
        _warnings = State(wrappedValue: warnings)
        _stars = State(wrappedValue: stars)
        _settings = State(wrappedValue: settings)

        _onboarding = State(wrappedValue: Self.onboarding(
            records, schedules: schedules,
            catalogue: reference.catalogue, settings: settings, coach: coach
        ))

        let (journey, queue) = Self.journey(
            baseURL: baseURL,
            identity: identity,
            sessions: sessions,
            scores: scores,
            rates: rates
        )
        _journey = State(wrappedValue: journey)

        (wrist, pulse) = Self.wristHandoff(over: outbox, through: watch, answering: journey)

        // Everything on this device that holds something about the person, for
        // a deletion to empty. Written out here because this is the only place
        // that knows the whole of it, and a store missing from this line is a
        // "delete everything" that quietly leaves that one behind. The queue
        // leads its own stores on purpose: erasing it first bumps its identity
        // epoch, so a restore walk suspended mid-merge abandons rather than
        // writing the erased identity's history back into the files erased
        // right after it.
        let personal: [any PersonalStore] = [
            queue, sessions, scores, rates, chats, records.profiles, records.consent,
            warnings, schedules, coach.plus, coach.heart, outbox, stars, settings,
        ]
        _account = State(wrappedValue: Self.account(
            baseURL: baseURL,
            identity: identity,
            emptying: personal,
            onIdentityChange: Self.identityChange(telling: watch, and: journey, reloading: own)
        ))
    }

    var body: some Scene {
        WindowGroup {
            // The whole of the chrome is `AppChrome`'s. Reminders live behind a
            // link in Settings; the subscription has no home of its own,
            // opening from whatever was locked.
            AppChrome(
                catalogue: reference.catalogue,
                occasions: reference.occasions,
                sessions: recorder,
                profiles: profiles,
                foundations: reference.foundations,
                assistant: assistant,
                chats: chats,
                router: router
            )
            .fullScreenCover(item: $firstRun) { gate in
                switch gate {
                case .onboarding:
                    if let onboarding {
                        OnboardingView(model: onboarding) {
                            firstRun = nil
                            self.onboarding = nil
                        }
                    }

                case .safety:
                    SafetyConsentView(store: consent) {
                        // First run's other exit: somebody who quit the flow
                        // once their answers were stored and comes back to the
                        // terms alone. Their profile may carry a reminder that
                        // onboarding's own last step never got to seed, and
                        // this is the only other place that ends first run.
                        Self.seedReminder(
                            profiles: profiles,
                            schedules: schedules,
                            catalogue: reference.catalogue
                        )
                        firstRun = nil
                    }
                }
            }
            // `brandText`, not `brand`: a tint mostly writes text — every
            // borderless button's label — and `brand` is pinned below its floor.
            .tint(Theme.Accent.brandText)
            // The palette resolves per appearance through the asset catalogue,
            // so one override here re-themes every screen; nil follows the
            // system, which keeps the default behaviour exactly today's.
            .preferredColorScheme(settings.appearance.colorScheme)
            // Outside the first-run presenter so its cover inherits the same
            // dependencies as the app chrome beneath it.
            .environment(settings)
            .environment(warnings)
            .environment(stars)
            .environment(account)
            .environment(plus)
            .environment(schedules)
            .environment(heart)
            .environment(journey)
            .environment(own)
            .environment(wrist)
            .environment(pulse)
            .environment(mood)
            .onChange(of: scenePhase, initial: true) { _, phase in
                guard phase == .active else { return }
                watch.push()
                Task { await reference.refresh() }
                // Cancelling leaves an entitlement until its paid period ends,
                // and that expiry produces no new purchase for `updates()`.
                if !Self.isUiTesting {
                    Task { await plus.refresh() }
                }
            }
            // A purchase has to reach the wrist without waiting for a relaunch:
            // somebody who subscribes to get the watch working with their phone
            // is, by definition, holding both. The outbox suppresses the push
            // when nothing changed, so this costs a comparison on the rare
            // launches where the tier moves at all.
            .onChange(of: plus.tier) { _, _ in
                watch.push()
            }
            .task {
                // A Live Activity outlives the process that requested one, so a
                // session that ended in a crash or a force quit leaves the lock
                // screen still asking somebody to breathe out. Nothing is
                // running at launch, so anything still up is stranded.
                await SessionActivity.clearStranded()

                // Returns early because the fixture *replaces* the sync — see
                // `installIfWanted`. `self.sessions` is qualified because
                // `async let sessions` below shadows the store for the scope.
                #if DEBUG
                    if await DemoPractice.installIfWanted(
                        sessions: self.sessions,
                        scores: scores,
                        rates: rates,
                        journey: journey
                    ) {
                        return
                    }
                #endif

                async let profile: Void = profiles.syncIfNeeded()
                async let sessions: Void = journey.sync()
                _ = await (profile, sessions)
            }
            // Its own task because it never returns: the first thing it does is
            // read the entitlement off the device and push anything the server
            // has not acknowledged, and then it listens for renewals and refunds
            // for as long as the app is running. Folded into the task above it
            // would hold the other two open forever.
            .task {
                guard !Self.isUiTesting else { return }
                await plus.watch()
            }
        }
    }
}
