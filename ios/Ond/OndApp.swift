import OndKit
import OndUI
import SwiftUI

/// What this install holds, and the one `init` that fills it in. The scene is
/// `OndAppScene`; the factories are `OndAppComposition`. The split costs
/// visibility: an extension in another file cannot see a private member, so
/// what the scene reads is internal. `identity`, `health` and `notifications`
/// are the three the scene never touches, and they keep `private`.
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
    let sessions = FileSessionStore()

    /// What the screens record through: the same file, with each kept session
    /// also credited to Health as Mindful Minutes. The journey's sync below
    /// keeps the bare store — history restored from the server is not new
    /// practice, and must never write to Health again.
    let recorder: any SessionRecording

    /// Controlled-pause scores, kept beside the sessions and for the same
    /// reason — Coach reads them with no network at all. Concrete for
    /// the reason the sessions are: a deletion has to be able to empty it.
    let scores = FileBoltScoreStore()

    /// Resting rates, beside the pauses and on the same terms. The second
    /// check-in, and the second store a deletion has to empty.
    let rates = FileRestingRateStore()

    /// The coach conversations, on this device only — the server keeps no
    /// transcript. Concrete for the reason the sessions are: a deletion has to
    /// be able to empty it.
    let chats = FileConversationStore()

    /// Hands the identity above to the watch app, which never mints one of its
    /// own. Composed here because the pairing belongs to the install rather
    /// than to any screen, and because this is where the identity already is.
    let watch: WatchLink

    /// Sends a discreet occasion to the wrist and waits out its answer. A
    /// plain `let`, not `@State`: it and the link are a pair joined in both
    /// directions, and `@State` would keep the first model while `route`
    /// pointed a rebuilt link at a second — acks would answer a model nothing
    /// reads, and every handoff would time out. `@Observable` keeps reads tracked.
    let wrist: WristLaunchModel

    /// Borrows the wrist's sensor for a session running here, so the screen can
    /// show a live heart rate. Beside `wrist` because it is the same arrangement
    /// pointed the other way — an order out, an answer back — and a plain `let`
    /// for the same reason: the link routes the wrist's readings onto it.
    let pulse: PulseMonitor

    /// The one connection to the health daemon, shared by everything that
    /// reads or writes Health data. One instance because its "already asked
    /// for the write grant" and "already logged a refusal" flags are
    /// per-process dedupe — three stores would ask and log three times.
    private let health = HealthKitHealthStore()

    /// Where a mood tapped before or after a session goes. Over the same store
    /// as everything else here, and holding nothing itself — see `MoodRecorder`,
    /// which is a way out to Health rather than a place a feeling is kept.
    let mood: MoodRecorder

    /// Where a tapped notification's request waits until there is a screen to
    /// answer it. A plain `let`, not `@State`, like everything composed here
    /// that outlives every screen — `@Observable` keeps the scene's reads
    /// tracked whichever way it is held.
    let router = NotificationRouter()

    /// Held for its lifetime and read by nothing: `UNUserNotificationCenter`
    /// keeps only a weak reference to its delegate, so the property is what
    /// stops a tapped reminder arriving at a deallocated object.
    private let notifications: NotificationDelegate

    /// In the environment rather than passed down, because the cue picker on the
    /// detail screen and the session that reads the setting are not adjacent.
    /// Built in `init` rather than here so the deletion list below can name the
    /// same instance the app reads.
    @State var settings: SessionSettings

    /// Whether this person has önd+. In the environment for the same
    /// reason `settings` is: the surfaces that offer a subscription — the
    /// assistant's two strips, and the paywall they open — are nowhere near
    /// here, and threading a parameter through every screen between would touch
    /// every one of them.
    @State var plus: SubscriptionStore

    /// Whether the safety terms have been agreed to, and the record of it. Held
    /// here rather than passed into onboarding alone because it is also what
    /// decides whether somebody who onboarded before that step existed is asked
    /// on this launch.
    @State var consent: SafetyConsentStore

    /// The per-technique warnings — which of the two contraindicated exercises'
    /// notes this person has accepted, and whether they asked for them to stay
    /// away. In the environment because the session screen that shows them can
    /// be covered over any tab; composed here so the deletion list below can
    /// empty it.
    @State var warnings: TechniqueWarningStore

    /// The stops this person starred, so they sit near the top of Home's sheet
    /// and the lists. Composed here rather than beside Home for the reason
    /// `warnings` is: the deletion list below has to be able to empty it, and
    /// this is the only place that knows the whole of that list.
    @State var stars: StarredStopStore

    /// What Home's button starts by default — the sheet's one choice. Composed
    /// here on `stars`' reasoning.
    @State var choice: HomeChoiceStore

    /// The heart-trends opt-in and the summary it unlocks, shared between the
    /// Settings toggle that flips it and the assistant that asks it per
    /// request. Constructed here — not file-scoped beside the assistant — so
    /// the one store holding something personal is built in sight of the
    /// deletion list below that has to empty it.
    @State var heart: HealthContextModel

    /// The assistant's repository, built here because its health context is
    /// the store above, which only this root may construct. `@State` like that
    /// store: the two are joined by a captured reference, and a rebuilt `App`
    /// value must discard the pair together, not split the kept store from a
    /// remade assistant reading a copy.
    @State var assistant: any AssistantReading

    /// Holds the onboarding answers and knows whether they have been given.
    @State var profiles: ProfileStore

    /// Signing in with Apple, signing out, and staying local-only. In the
    /// environment because the rows that offer it are in Settings, two pushes
    /// below a tab root that has no use for it.
    @State var account: AccountModel

    /// What this install still owes before anybody breathes. One enum, not a
    /// flag each — the covers are mutually exclusive by construction. Separate
    /// from `profiles.hasCompletedOnboarding`, which is set the moment the
    /// last answer is stored: a screen dismissed on that flag would vanish
    /// before the person saw the last card.
    @State var firstRun: FirstRunGate?

    /// The first-run flow, built here rather than inside the cover: a
    /// `fullScreenCover` closure runs on every body evaluation, and building
    /// a model snapshots four `UserDefaults` preferences as the flow's
    /// baseline. Nil on every launch but the first, so an onboarded install
    /// does not carry the flow's dependencies for the process's life.
    @State var onboarding: OnboardingModel?

    /// The catalogue, the foundations and the occasions, shared by every tab:
    /// home's dial and the techniques list are two views onto the same load.
    /// Built here, at the composition root, so a preview or a test can
    /// substitute the reading behind all three without touching the network.
    @State var reference: Reference

    /// The exercises this person wrote for themselves. Its own model rather
    /// than part of the catalogue's: they come from a different service, they
    /// need the identity, and they are written as well as read.
    @State var own: UserTechniqueModel

    /// The standing appointments, backed by local notifications. Composed in
    /// `init` so the deletion below can reach it — the pending requests are
    /// iOS's, and nothing else can take them back. It outlives the Settings
    /// screen, because the notifications must stay honest either way.
    @State var schedules: ScheduleStore

    /// Totals, streaks, and the boards. Local-first: everything it shows about
    /// this person is folded from the three stores above, so the tab is complete
    /// before the sync it starts has finished.
    @State var journey: JourneyModel

    /// Watched so the watch's copy of the identity and the personal best is
    /// refreshed on every foreground, rather than only on the launch that built
    /// this scene.
    @Environment(\.scenePhase) var scenePhase

    init() {
        // First, so the display face resolves before any scene draws the
        // wordmark. Registration is idempotent; this call is about ordering.
        Theme.Typeface.register()

        let identity = identity
        let baseURL = AppConfiguration.apiBaseURL
        recorder = MindfulMinutesRecorder(wrapping: sessions, health: health)
        mood = MoodRecorder(store: health)

        // Ahead of the outbox, which reads the tier and the agreed terms at
        // every hand-over so the wrist knows what it may do with this phone and
        // whether it still has to ask. Nothing else here needs either this
        // early; the ordering is the dependency.
        let coach = Self.coach(baseURL: baseURL, identity: identity, health: health)
        _plus = State(wrappedValue: coach.plus)
        _heart = State(wrappedValue: coach.heart)
        _assistant = State(wrappedValue: coach.assistant)

        let records = Self.firstRunRecords(baseURL: baseURL, identity: identity)
        _profiles = State(wrappedValue: records.profiles)
        _consent = State(wrappedValue: records.consent)
        _firstRun = State(wrappedValue: Self.firstRunGate(for: records))

        let (outbox, watch) = Self.pairing(
            identity: identity, scores: scores, plus: coach.plus, consent: records.consent
        )
        self.watch = watch

        let schedules = ScheduleStore(notifier: NotificationScheduler())
        _schedules = State(wrappedValue: schedules)

        notifications = NotificationDelegate.installed(routing: router)

        let reference = Reference(baseURL: baseURL, identity: identity)
        _reference = State(wrappedValue: reference)

        let own = UserTechniqueModel(store: Self.ownExercises(baseURL: baseURL, identity: identity))
        _own = State(wrappedValue: own)

        // The four stores composed from nothing at all. Together on one line
        // only because each is a local the deletion list below has to name,
        // which is all they have in common.
        let (warnings, stars, choice, settings) =
            (TechniqueWarningStore(), StarredStopStore(), HomeChoiceStore(), SessionSettings())
        _warnings = State(wrappedValue: warnings)
        _stars = State(wrappedValue: stars)
        _choice = State(wrappedValue: choice)
        _settings = State(wrappedValue: settings)

        _onboarding = State(wrappedValue: Self.onboarding(
            records, schedules: schedules,
            catalogue: reference.catalogue, settings: settings, coach: coach
        ))

        let (journey, queue) = Self.journey(
            baseURL: baseURL, identity: identity, sessions: sessions, scores: scores, rates: rates
        )
        _journey = State(wrappedValue: journey)

        (wrist, pulse) = Self.wristHandoff(over: outbox, through: watch, answering: journey)

        // Everything on this device that holds something about the person; a
        // store missing from this line survives "delete everything". The
        // queue leads on purpose: erasing it first bumps its identity epoch,
        // so a restore walk suspended mid-merge abandons rather than writing
        // the erased history back into the files erased right after it.
        _account = State(wrappedValue: Self.account(
            baseURL: baseURL,
            identity: identity,
            emptying: [
                queue, sessions, scores, rates, chats, records.profiles, records.consent,
                warnings, schedules, coach.plus, coach.heart, outbox, stars, choice, settings,
            ],
            onIdentityChange: Self.identityChange(telling: watch, and: journey, reloading: own)
        ))
    }
}
