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

    /// The one connection to the health daemon this app opens, on the phone
    /// root's reasoning: the mindful-minutes write and the sensor a phone session
    /// borrows are the same store, and its "already asked" flags are per-process
    /// dedupe that two instances would defeat.
    private let health = HealthKitHealthStore()

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

    /// Held only so the system installs it: the delegate answers the phone's
    /// launch, and nothing here reads it.
    @WKApplicationDelegateAdaptor(WatchAppDelegate.self) private var delegate

    /// The wrist's half of the handoff: what an order resolves to, whether it
    /// can be taken up at all, and the answer sent back. In `OndKit` because
    /// that sequence is where the states are, and this target has no tests.
    @State private var orders: WristOrderModel

    init() {
        let baseURL = WatchConfiguration.apiBaseURL
        recorder = MindfulMinutesRecorder(wrapping: sessions, health: health)

        // One repository behind both models, so the techniques and the routes
        // that route to them come from the same fetch-then-cache-then-seed
        // fallback and cannot disagree about which build they describe.
        let techniques = CachedTechniqueRepository(
            caching: TechniqueRepository(baseURL: baseURL, identity: identity)
        )
        let catalogue = TechniqueListModel(techniques: techniques)
        let routes = RoutesModel(routes: techniques)
        _catalogue = State(wrappedValue: catalogue)
        _routes = State(wrappedValue: routes)

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
            stores: [queue, sessions, scores, rates],
            // Named here rather than defaulted inside the inbox: it is a fourth
            // thing this wrist persists, and this list is where those are said
            // out loud.
            orders: WatchOrderLedger(defaults: .standard)
        )
        _phone = State(wrappedValue: inbox)
        let link = PhoneLink(inbox: inbox)
        self.link = link

        _orders = State(
            wrappedValue: WristOrderModel(
                catalogue: catalogue,
                routes: routes,
                // A *claimed* budget is the honest answer to "is this wrist
                // mid-cadence": every cadence long enough to need one takes it,
                // whether the phone ordered it or somebody started it here. Not a
                // merely running workout — the launch itself takes one of those
                // before there is anything to spend it on, so asking that
                // question has the wrist decline every order it is sent.
                isBusy: { WorkoutRuntime.shared.isClaimed },
                answer: { link.acknowledge($0) }
            )
        )
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
                // The routes join the catalogue here, rather than waiting for
                // the Moments screen: an order the phone places names its
                // occasion by slug, and routes already in hand are what let the
                // wrist put the moment's own name above the session instead of
                // the exercise's.
                async let catalogue: Void = catalogue.loadIfNeeded()
                async let routes: Void = routes.loadIfNeeded()
                async let sync: Void = journey.sync()
                _ = await (catalogue, routes, sync)
            }
            // An identity arriving is the moment a backlog recorded anonymously
            // becomes attributable — and, the first time, the moment the phone's
            // own history can be restored onto the wrist.
            .onChange(of: phone.userId) { _, userId in
                guard userId != nil else { return }
                Task { await journey.sync() }
            }
            // The order the phone placed, once the inbox has admitted it.
            // Consumed rather than read, so no path has to remember to clear it.
            .onChange(of: phone.order) { _, order in
                guard order != nil, let taken = phone.takeOrder() else { return }
                Task { await orders.take(up: taken) }
            }
            // A sheet over whatever the wrist was showing: the order is a
            // request to act now, so it does not wait behind a menu.
            .sheet(item: presentedEngagement) { engagement in
                switch engagement {
                case let .breathe(moment):
                    DiscreetSessionView(
                        model: DiscreetSessionModel(
                            technique: moment.technique,
                            occasionSlug: moment.occasionSlug,
                            cues: WatchHapticController(settings: settings),
                            recorder: recorder
                        ),
                        occasionName: moment.occasionName
                    ) { record in
                        Task { await finish(moment.order, having: record) }
                    }

                case let .sharePulse(order):
                    PulseShareView(
                        relay: PulseRelay(order: order) { await link.share($0) },
                        health: health
                    )
                }
            }
        }
    }

    /// What the sheet presents, read from `WristOrderModel` so that model stays
    /// the one owner of what the wrist is engaged in — and told when the screen
    /// goes, so it is free to accept the next order.
    private var presentedEngagement: Binding<WristEngagement?> {
        Binding {
            orders.engagement
        } set: { engagement in
            if engagement == nil {
                orders.dismiss()
            }
        }
    }

    /// Closes the loop on an ordered session: the record has been stored by the
    /// time this runs (`DiscreetSessionModel` guarantees the ordering), so the
    /// sync has something to send and the notice something to point at.
    ///
    /// A discarded false start reports nothing. Nothing was stored, so the
    /// notice would send the phone looking for a session that does not exist —
    /// and the sync would drain files that gained nothing.
    private func finish(_ order: WatchSessionOrder, having record: SessionRecord?) async {
        guard record != nil else { return }

        await journey.sync()
        link.report(WatchSessionNotice(orderId: order.id))
    }
}
