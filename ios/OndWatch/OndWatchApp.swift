import OndKit
import OndUI
import SwiftUI

/// The watch app's entry point, and the one place its dependencies are wired.
///
/// The same composition as the phone's, over the same types: the session engine,
/// the offline catalogue cache, the local session store, and the sync queue are
/// all platform-neutral by construction, so the wrist reuses them rather than
/// reimplementing them. Two things differ, and both are consequences of the
/// watch never minting an identity — the identity store is the provisioned one,
/// and a `PhoneLink` listens for the id that fills the `WatchHandoffInbox`.
@main
struct OndWatchApp: App {
    /// Empty until the phone has been in range once. Everything below tolerates
    /// that: the catalogue ships in the bundle and is refreshed by a public RPC,
    /// sessions record locally, and the sync queue simply keeps its backlog
    /// until there is somebody to attribute it to.
    private let identity = ProvisionedUserIdentityStore()

    /// One store for the whole app, and the same file the sync queue drains.
    ///
    /// Concrete rather than `any SessionRecording`, because the inbox below also
    /// needs its other face: what this wrist holds of a person, for the context
    /// that says they have deleted their account.
    private let sessions = FileSessionStore()

    /// What the screens record through: the same file, with each kept session
    /// also credited to Health as Mindful Minutes — the wrist writes its own,
    /// so a session breathed away from the phone still counts. The sync queue
    /// keeps the bare store above; restored history is not new practice.
    private let recorder: any SessionRecording

    @State private var catalogue: TechniqueListModel
    @State private var routes: RoutesModel
    @State private var journey: JourneyModel

    /// Everything the phone has told this wrist. In the environment, because
    /// the screen that renders the mirrored best is three pushes from here.
    @State private var phone: WatchHandoffInbox

    /// The radio that fills it. A stored `let` rather than `@State` because
    /// nothing observes it and `WCSession.delegate` is weak — something has to
    /// hold this for the life of the app or the delegate quietly goes away.
    private let link: PhoneLink

    /// The one preference the wrist owns, held here so the settings screen and
    /// the cue controller a session is composed with are looking at the same
    /// switch.
    @State private var settings = WatchSettings()

    init() {
        let baseURL = WatchConfiguration.apiBaseURL
        recorder = MindfulMinutesRecorder(wrapping: sessions, health: HealthKitHealthStore())

        // One repository behind both models, so the techniques and the routes
        // that route to them come from the same fetch-then-cache-then-seed
        // fallback and cannot disagree about which build they describe.
        let techniques = CachedTechniqueRepository(
            caching: TechniqueRepository(baseURL: baseURL, identity: identity)
        )
        _catalogue = State(wrappedValue: TechniqueListModel(techniques: techniques))
        _routes = State(wrappedValue: RoutesModel(routes: techniques))

        let journeys = JourneyRepository(baseURL: baseURL, identity: identity)
        // Present so the queue and the model are the ones the phone uses,
        // unchanged. Both stay empty on the wrist: the check-ins are phone
        // screens — one needs a stopwatch the wearer can stop, the other a
        // minute of tapping — and the pause the first produces reaches here over
        // the pairing.
        let scores = FileBoltScoreStore()
        let rates = FileRestingRateStore()
        let queue = SessionSyncQueue(
            sessions: sessions,
            scores: scores,
            rates: rates,
            journeys: journeys
        )
        _journey = State(
            wrappedValue: JourneyModel(
                sessions: sessions,
                scores: scores,
                rates: rates,
                journeys: journeys,
                queue: queue
            )
        )

        // Everything on this wrist that is about the person rather than about
        // the app. The phone's list is longer because the phone holds more; this
        // one is the sessions breathed here, the empty check-in files beside
        // them, and the ledger of what has already gone up. The queue leads for
        // the phone list's reason: erased first, its epoch stops a suspended
        // restore writing into the files erased after it.
        let inbox = WatchHandoffInbox(
            identity: identity,
            stores: [queue, sessions, scores, rates]
        )
        _phone = State(wrappedValue: inbox)
        link = PhoneLink(inbox: inbox)
    }

    var body: some Scene {
        WindowGroup {
            NavigationStack {
                RootMenuView(
                    catalogue: catalogue,
                    routes: routes,
                    sessions: recorder,
                    journey: journey
                )
            }
            .tint(Theme.Accent.brand)
            // In the environment rather than passed down: the screens that read
            // these sit two or three pushes from here, and the menu in between
            // has no use for either.
            .environment(phone)
            .environment(settings)
            .task {
                link.activate()
                // Started here rather than left to the Exercises screen, so the
                // catalogue is in hand by the time somebody has tapped through
                // the menu. `loadIfNeeded` is what makes that a shared fetch
                // rather than a second one.
                async let catalogue: Void = catalogue.loadIfNeeded()
                async let sync: Void = journey.sync()
                _ = await (catalogue, sync)
            }
            // An identity arriving is the moment a backlog recorded anonymously
            // becomes attributable — and, the first time, the moment the phone's
            // own history can be restored onto the wrist.
            .onChange(of: phone.userId) { _, userId in
                guard userId != nil else { return }
                Task { await journey.sync() }
            }
        }
    }
}
