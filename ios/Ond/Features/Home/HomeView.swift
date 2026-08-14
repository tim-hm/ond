import OndKit
import OndUI
import SwiftUI

/// Home: how the practice is going, what to breathe next, and the doors to
/// everything about it.
///
/// The screen the Journey tab and the old Breathe board became. Keeping them
/// apart cost a tab each and made two screens that were both half-answers: a
/// board of things to breathe that said nothing about whether you had, and a
/// page of numbers with no way to act on them. Everything here is folded from
/// this device, so it is complete before the sync behind it has started and
/// stays complete in airplane mode.
///
/// It scrolls, which the board could not. The old screen's hard constraint —
/// nothing on Home may be a vertical scroll view, because a large navigation
/// title collapses against the nearest one and did so inconsistently — was a
/// constraint of a *paging* layout, where the scroll position on arrival was
/// whatever the last page turn left it at. A document that always opens at the
/// top collapses its title the same way every time, which is the behaviour the
/// other three tabs have.
///
/// **What to offer is `HomeShelf`'s, not this file's.** The suggestion, the
/// rerun and the shelf are three sections of one fold, including the rule that
/// no stop appears in two of them; drawing them is all that is left here. That
/// split is what keeps every one of those rules under a test, since the app
/// target has no bundle to put one in.
///
/// There is no separate notices strip, and that is a decision rather than an
/// omission: the one notice worth showing is a paused streak, the practice
/// summary is where `JourneyStats` says that in its own words, and a line above
/// the card repeating it would be one fact printed twice.
struct HomeView: View {
    let catalogue: TechniqueListModel
    let routes: RoutesModel
    let sessions: any SessionRecording

    /// The exercises this person composed, so a star on one resolves to a row —
    /// and so the Sessions chart counts them. Beside the catalogue rather than
    /// folded into it, for the reason `AppRoots` keeps them apart: two services,
    /// two loads, and only one of them needs an identity.
    let own: UserTechniqueModel

    /// The totals, the streak and the history — all of it local, all of it
    /// already there.
    let journey: JourneyModel

    /// Read by Settings and for the name the leaderboard door reports somebody
    /// as listed under.
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

    // MARK: the screen

    /// Home arrives whole or not at all: every offer on it resolves a slug
    /// against the catalogue, so there is nothing to draw until that has landed
    /// — and something to say when it never does.
    @ViewBuilder
    private var content: some View {
        switch catalogue.state {
        case .loading:
            ProgressView()

        case let .loaded(techniques) where techniques.isEmpty:
            ContentUnavailableView {
                Label("The catalogue is empty", systemImage: "wind")
            } description: {
                Text("The server answered, but with no exercises in it.")
            } actions: {
                retryButton
            }

        case .loaded:
            scroll

        case let .failed(message):
            ContentUnavailableView {
                Label("Can't reach the catalogue", systemImage: "wifi.exclamationmark")
            } description: {
                Text(message)
            } actions: {
                retryButton
            }
        }
    }

    /// Both loads, because the routes are what turn half of this screen from
    /// exercises into protocols — and a person who has just watched one fail has
    /// no way to tell which of the two it was.
    private var retryButton: some View {
        Button("Try again") {
            Task {
                async let routed: Void = routes.refresh()
                await catalogue.refresh()
                await routed
            }
        }
    }

    private var scroll: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.loose) {
                PracticeSummaryCard(stats: journey.stats) {
                    HistoryView(model: journey, catalogue: catalogue, own: own)
                }

                nextUp
                starred
                leaderboardDoor
            }
            .padding(Theme.Spacing.standard)
        }
    }

    /// Two offers, and neither is a browse: what the hour suggests, and what was
    /// breathed last.
    ///
    /// Both are rows rather than one being a hero, because they answer the same
    /// question from two directions — the app's guess and this person's own last
    /// answer — and putting either above the other would be Home claiming to
    /// know which is better. The shelf drops the second where it would repeat
    /// the first, so the pair is never one exercise twice.
    @ViewBuilder
    private var nextUp: some View {
        if let suggested = shelf?.suggested {
            LabelledSection(title: "Suggested now") {
                row(suggested)
            }
        }

        if let lastRun = shelf?.lastRun {
            LabelledSection(title: "Pick up where you left off") {
                VStack(alignment: .leading, spacing: Theme.Spacing.tight) {
                    row(lastRun.stop)

                    Text(lastRun.at.formatted(.relative(presentation: .named)))
                        .font(.caption)
                        .foregroundStyle(Theme.Ink.tertiary)
                }
            }
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

    /// The leaderboard's own screen holds the gate — it draws the offer where
    /// the boards would be — so this door opens at every tier. Sessions no
    /// longer needs a second door here: the practice summary is its way in.
    private var leaderboardDoor: some View {
        DoorCard(
            title: "Leaderboards",
            caption: profiles.profile.displayName.isEmpty
                ? "Optional, and off until you pick a name."
                : "You're listed as \(profiles.profile.displayName)."
        ) {
            LeaderboardView(model: journey, profiles: profiles)
        }
    }
}
