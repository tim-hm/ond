import OndKit
import OndUI
import SwiftUI

/// Home: how the practice stands and what to breathe next.
///
/// Everything here is either useful now or starts in one tap. The settled shape
/// belongs to Progress, while four compact cards keep the rhythm, recency,
/// current suggestion and repeat action together above the stops this person
/// chose to keep near.
///
/// It scrolls, which the board could not. The old screen's hard constraint —
/// nothing on Home may be a vertical scroll view, because a large navigation
/// title collapses against the nearest one and did so inconsistently — was a
/// constraint of a *paging* layout, where the scroll position on arrival was
/// whatever the last page turn left it at. A document that always opens at the
/// top collapses its title the same way every time, which is the behaviour the
/// other four tabs have.
///
/// **What to offer is `HomeShelf`'s, not this file's.** The suggestion, repeat
/// action and shelf are one fold; drawing them is all that is left here. The
/// action cards may name the same stop because they answer different questions,
/// while Starred omits anything already actionable above. That split keeps the
/// rules under test, since the app target has no bundle to put one in.
///
/// Last-practice recency uses the system's relative time. Before the first
/// session its card says what will make that action available rather than
/// treating an empty history as an error.
struct HomeView: View {
    let catalogue: TechniqueListModel
    let routes: RoutesModel
    let sessions: any SessionRecording

    /// The exercises this person composed, so a star on one resolves to a row —
    /// and so the Progress chart counts them. Beside the catalogue rather than
    /// folded into it, for the reason `AppRoots` keeps them apart: two services,
    /// two loads, and only one of them needs an identity.
    let own: UserTechniqueModel

    /// The history behind the repeat card and last-session status.
    let journey: JourneyModel

    /// Read by Settings, which remains in Home's toolbar.
    let profiles: ProfileStore

    /// Read by the rows for the lengths they print, and by the fold in
    /// `HomeView+Folding` for the lengths it bakes into a stop — which is why
    /// these three are not `private`.
    @Environment(SessionSettings.self) var settings
    @Environment(SubscriptionStore.self) private var plus

    /// The stars. In the environment beside the other two rather than passed
    /// in, because it is the install's and outlives this screen — and because
    /// the deletion list in `OndApp` is what has to reach it, not `AppRoots`.
    @Environment(StarredStopStore.self) var stars

    /// Watched so the hour's suggestion is re-read when somebody comes back to
    /// the app, rather than staying on the goal that fitted whenever they last
    /// opened it — a phone left on the desk at five would still be offering
    /// "focus" at ten at night.
    @Environment(\.scenePhase) private var scenePhase

    /// What Home has to offer, or nil before the catalogue has landed.
    ///
    /// Optional rather than an empty value, because "nothing has loaded" and
    /// "you have starred nothing" are different screens and an empty sentinel
    /// says both: a subscriber with a full shelf met the "Star a protocol…"
    /// invitation for the beat before the first fold.
    @State var shelf: HomeShelf?

    @State private var launcher: StopLauncher

    init(
        catalogue: TechniqueListModel,
        routes: RoutesModel,
        sessions: any SessionRecording,
        own: UserTechniqueModel,
        journey: JourneyModel,
        profiles: ProfileStore
    ) {
        self.catalogue = catalogue
        self.routes = routes
        self.sessions = sessions
        self.own = own
        self.journey = journey
        self.profiles = profiles
        _launcher = State(wrappedValue: StopLauncher(sessions: sessions))
    }

    var body: some View {
        NavigationStack {
            content
                .paletteGround()
                .navigationTitle("Home")
                // The gear is here because a tab bar is for content sections and
                // settings is not one. It sat in Journey's toolbar for the same
                // reason, beside the numbers about the person the settings
                // belong to.
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        NavigationLink {
                            SettingsView(catalogue: catalogue, profiles: profiles)
                        } label: {
                            Label("Settings", systemImage: "gearshape")
                        }
                    }
                }
                .stopLauncher(launcher)
        }
        // The local read first, so the numbers are complete before anything
        // touches the network; the two fetches then run behind what is already
        // drawn. Nothing here folds — the triggers below do, because every one
        // of these lands as a change to something they watch.
        .task {
            await journey.refresh()

            async let routed: Void = routes.loadIfNeeded()
            await catalogue.loadIfNeeded()
            await routed

            await journey.sync()
        }
        // Separate from the catalogue's load rather than sequenced after it, the
        // same way the Exercises tab does it: two services, and eleven curated
        // exercises should not wait on somebody's own.
        .task { await own.loadIfNeeded() }
        // One trigger per input, and each folds only what that input feeds.
        //
        // The history keys on the records rather than on their count: a sync
        // that amends a session without adding one changes every number on this
        // screen and would not move a count, and a delete followed by a restore
        // would move it back.
        .onChange(of: journey.history, initial: true) { _, _ in
            foldShelf()
        }
        // A late catalogue is the ordinary first launch, not an edge: this
        // screen's fold silently answers nothing until it lands, and without
        // this it would go on answering nothing after it did.
        .onChange(of: loaded.map(\.id)) { _, _ in
            foldShelf()
        }
        .onChange(of: routes.available) { _, _ in foldShelf() }
        // The authored list changes on another tab — somebody writes an exercise
        // in the composer, which stars it so it lands here. A tab root is not
        // torn down when you leave it, so nothing else would notice.
        .onChange(of: own.techniques.map(\.id)) { _, _ in
            foldShelf()
        }
        // A star made on an exercise's own screen or on the Protocols list has
        // to reach the shelf, and both taps happen on another tab.
        .onChange(of: stars.starred) { _, _ in foldShelf() }
        // Re-dialling an exercise in Exercises moves the length every row here
        // states — and the row owes that number, because the tap plays it.
        .onChange(of: settings.overridesBySlug) { _, _ in foldShelf() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                foldShelf()
            }
        }
    }

    /// Home arrives whole or not at all: every offer on it resolves a slug
    /// against the catalogue, so there is nothing to draw until that has landed
    /// — and something to say when it never does.
    @ViewBuilder
    private var content: some View {
        switch catalogue.state {
        case .loading:
            ProgressView()

        case let .loaded(techniques) where techniques.isEmpty:
            EmptyCatalogueView(retry: retryReferenceData)

        case .loaded:
            scroll

        case let .failed(message):
            ReferenceRetryView(
                title: "Can't reach the catalogue",
                message: message,
                retry: retryReferenceData
            )
        }
    }

    /// Both loads, because the routes are what turn half of this screen from
    /// exercises into protocols — and a person who has just watched one fail has
    /// no way to tell which of the two it was.
    private func retryReferenceData() {
        Task {
            async let routed: Void = routes.refresh()
            await catalogue.refresh()
            await routed
        }
    }

    private var scroll: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.loose) {
                HomePracticeGrid(
                    stats: journey.stats,
                    lastSessionAt: journey.history.first?.startedAt,
                    suggested: shelf?.suggested,
                    repeatLast: shelf?.lastRun?.stop,
                    tier: plus.tier
                ) { stop in
                    launcher.begin(stop)
                }
                starred
            }
            .padding(Theme.Spacing.standard)
        }
    }

    /// What somebody chose to keep in front of them, or the quiet line saying
    /// how to.
    ///
    /// The empty state is one sentence and no illustration: it is an invitation
    /// rather than a feature nobody found, and a card explaining starring on a
    /// screen already full of things to read would be an advertisement. It waits
    /// for the fold — `shelf` is nil until then — so nobody is invited to star
    /// something they starred last week.
    @ViewBuilder
    private var starred: some View {
        if let shelf {
            LabelledSection(title: "Starred") {
                if shelf.starred.isEmpty {
                    Text("Star a protocol or an exercise and it waits here.")
                        .font(.callout)
                        .foregroundStyle(Theme.Ink.secondary)
                } else {
                    VStack(spacing: Theme.Spacing.close) {
                        ForEach(shelf.starred) { stop in
                            row(stop)
                        }
                    }
                }
            }
        }
    }

    private func row(_ stop: DialStop) -> some View {
        StopRow(stop: stop, tier: plus.tier) { launcher.begin(stop) }
    }
}
