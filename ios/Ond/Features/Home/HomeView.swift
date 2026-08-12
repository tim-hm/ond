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
/// There is no separate notices strip, and that is a decision rather than an
/// omission: the one notice worth showing is a paused streak, `StreakCard` is
/// where `JourneyStats` says that in its own words, and a line above the card
/// repeating it would be one fact printed twice.
struct HomeView: View {
    let catalogue: TechniqueListModel
    let routes: RoutesModel
    let sessions: any SessionRecording

    /// The exercises this person composed, so a star on one resolves to a row.
    /// Beside the catalogue rather than folded into it, for the reason
    /// `AppRoots` keeps them apart: two services, two loads, and only one of
    /// them needs an identity.
    let own: UserTechniqueModel

    /// The totals, the streak and the history — all of it local, all of it
    /// already there.
    let journey: JourneyModel

    /// Read for the given name the header greets somebody by, and for the name
    /// the leaderboard door reports them as listed under.
    let profiles: ProfileStore

    @Environment(SessionSettings.self) private var settings
    @Environment(SubscriptionStore.self) private var plus

    /// The stars. In the environment beside the other two rather than passed
    /// in, because it is the install's and outlives this screen — and because
    /// the deletion list in `OndApp` is what has to reach it, not `AppRoots`.
    @Environment(StarredStopStore.self) private var stars

    /// What is already this person's: the stars, and the last thing breathed.
    ///
    /// Held rather than recomputed in `body` because it is a join over the whole
    /// catalogue and the whole history, and as a computed property it would run
    /// on every pass — every tier change, every scroll that invalidates. It is
    /// rebuilt when one of its four inputs actually moves.
    @State private var shelf = HomeShelf(
        techniques: [], routes: .none, history: [], starred: []
    )

    /// The four weeks behind the chart, rebuilt beside the shelf and for the
    /// same reason.
    @State private var rhythm = PracticeRhythm(sessions: [], goals: [:])

    /// What the hour offers, or nil before the catalogue has landed.
    ///
    /// State rather than a computed property because building it reads the
    /// clock, and a recommendation that could change between two layout passes
    /// is not one anybody can reason about.
    @State private var suggested: DialStop?

    @State private var launcher: StopLauncher

    init(
        catalogue: TechniqueListModel,
        routes: RoutesModel,
        sessions: any SessionRecording,
        own: UserTechniqueModel,
        journey: JourneyModel,
        profiles: ProfileStore,
        settings: SessionSettings,
        plus: SubscriptionStore,
        wrist: WristLaunchModel
    ) {
        self.catalogue = catalogue
        self.routes = routes
        self.sessions = sessions
        self.own = own
        self.journey = journey
        self.profiles = profiles
        _launcher = State(wrappedValue: StopLauncher(
            sessions: sessions,
            settings: settings,
            plus: plus,
            wrist: wrist
        ))
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Spacing.loose) {
                    welcome
                    StreakCard(stats: journey.stats)
                    totals

                    if rhythm.isWorthCharting {
                        PracticeChartView(rhythm: rhythm)
                    }

                    nextUp
                    starred
                    doors
                }
                .padding(Theme.Spacing.standard)
            }
            .paletteGround()
            .navigationTitle("Home")
            // The gear is here because a tab bar is for content sections and
            // settings is not one. It sat in Journey's toolbar for the same
            // reason, beside the numbers about the person the settings belong
            // to.
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    NavigationLink {
                        SettingsView(catalogue: catalogue, profiles: profiles)
                    } label: {
                        Label("Settings", systemImage: "gearshape")
                    }
                }
            }
            .stopLauncher(launcher) {
                // A finished session moves the totals, the streak, the chart and
                // what there is to pick up again — all of it downstream of the
                // history this re-reads.
                Task {
                    await journey.refresh()
                    rebuild()
                }
            }
        }
        // The local read first, so the screen is complete before anything
        // touches the network; the two fetches then run behind what is already
        // drawn.
        .task {
            await journey.refresh()
            rebuild()

            async let routed: Void = routes.loadIfNeeded()
            await catalogue.loadIfNeeded()
            await routed
            rebuild()

            await journey.sync()
            rebuild()
        }
        // Separate from the catalogue's load rather than sequenced after it, the
        // same way the Exercises tab does it: two services, and eleven curated
        // exercises should not wait on somebody's own.
        .task {
            await own.loadIfNeeded()
            rebuild()
        }
        // The authored list changes on another tab — somebody writes an exercise
        // in the composer, which stars it so it lands here. This screen's tasks
        // ran long before that, and a tab root is not torn down when you leave
        // it.
        .onChange(of: own.techniques.map(\.id)) { _, _ in rebuild() }
        // A star made on an exercise's own screen or on the Protocols list has
        // to reach the shelf, and both taps happen on another tab.
        .onChange(of: stars.starred) { _, _ in rebuild() }
        // A session deleted from the History screen behind a door on this one,
        // which is a push rather than a cover — so nothing else here notices.
        .onChange(of: journey.history.count) { _, _ in rebuild() }
    }

    // MARK: the sections

    /// The one line that is about the person rather than the practice.
    ///
    /// Content rather than the navigation title, so the title stays "Home" and
    /// matches the other three tabs — a large title reading "Welcome back, Tim"
    /// would collapse into a greeting in the nav bar, which is not what a nav
    /// bar is for.
    ///
    /// The name is optional and one tap from being skipped, so the sentence has
    /// to read as well without it.
    private var welcome: some View {
        let name = profiles.profile.givenName

        return Text(name.isEmpty ? "Welcome back." : "Welcome back, \(name).")
            .font(.title3.weight(.semibold))
            .foregroundStyle(Theme.Ink.secondary)
    }

    /// Days first — see `JourneyStats.daysPractised` for why it leads.
    private var totals: some View {
        HStack(spacing: Theme.Spacing.standard) {
            StatTile(value: journey.stats.daysPractised, label: "days")
            StatTile(value: journey.stats.sessions, label: "sessions")
            StatTile(value: journey.stats.minutes, label: "minutes")
        }
    }

    /// Two offers, and neither is a browse: what the hour suggests, and what was
    /// breathed last.
    ///
    /// Both are rows rather than one being a hero, because they answer the same
    /// question from two directions — the app's guess and this person's own last
    /// answer — and putting either above the other would be Home claiming to
    /// know which is better.
    @ViewBuilder
    private var nextUp: some View {
        if let suggested {
            section("Suggested now") {
                StarredStopRow(
                    stop: suggested,
                    tier: plus.tier,
                    isStarred: stars.starred.contains(suggested.id),
                    star: { stars.toggle(suggested.id) },
                    start: { launcher.begin(suggested) }
                )
            }
        }

        if let lastRun = shelf.lastRun {
            section("Pick up where you left off") {
                VStack(alignment: .leading, spacing: Theme.Spacing.tight) {
                    StarredStopRow(
                        stop: lastRun.stop,
                        tier: plus.tier,
                        isStarred: stars.starred.contains(lastRun.stop.id),
                        star: { stars.toggle(lastRun.stop.id) },
                        start: { launcher.begin(lastRun.stop) }
                    )

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
    /// screen already full of things to read would be an advertisement.
    private var starred: some View {
        section("Starred") {
            if shelf.starred.isEmpty {
                Text("Star a protocol or an exercise and it waits here.")
                    .font(.callout)
                    .foregroundStyle(Theme.Ink.secondary)
            } else {
                VStack(spacing: Theme.Spacing.close) {
                    ForEach(shelf.starred) { stop in
                        StarredStopRow(
                            stop: stop,
                            tier: plus.tier,
                            isStarred: true,
                            star: { stars.toggle(stop.id) },
                            start: { launcher.begin(stop) }
                        )
                    }
                }
            }
        }
    }

    /// The two rooms the numbers above open onto.
    ///
    /// The leaderboard's own screen holds the gate — it draws the offer where
    /// the boards would be — so this door opens at every tier. A door that
    /// refused to open would be one nobody could find out what was behind.
    private var doors: some View {
        VStack(spacing: Theme.Spacing.standard) {
            DoorCard(
                title: "Sessions",
                caption: journey.history.isEmpty
                    ? "Every session you breathe lands here."
                    : "All \(journey.history.count) of them, newest first."
            ) {
                HistoryView(model: journey, catalogue: catalogue)
            }

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

    private func section(
        _ title: String,
        @ViewBuilder content: () -> some View
    ) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.close) {
            Text(title)
                .font(.title3.weight(.semibold))
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: what the screen is folded from

    /// Rebuilds everything derived from the catalogue, the routes, the history
    /// and the stars.
    ///
    /// One function for all four folds because they share the join — the
    /// catalogue keyed by slug — and because a screen where the shelf and the
    /// chart could be built from two different histories is one where the rerun
    /// row and the last bar disagree.
    ///
    /// Silent until the catalogue has landed. Everything here resolves a slug
    /// against it, so folding early would produce an empty shelf and a blank
    /// chart that the next call replaces a beat later.
    private func rebuild() {
        guard case let .loaded(techniques) = catalogue.state else { return }

        let dialled = techniques
            .reduce(into: [String: TechniqueOverrides]()) { dialled, technique in
                dialled[technique.slug] = settings.overrides(for: technique)
            }

        shelf = HomeShelf(
            techniques: techniques,
            routes: routes.available,
            history: journey.history,
            starred: stars.starred,
            dialled: dialled,
            authored: own.techniques
        )

        rhythm = PracticeRhythm(
            sessions: journey.history,
            goals: techniques.reduce(into: [:]) { goals, technique in
                goals[technique.slug] = technique.goal
            }
        )

        suggested = HomeSuggestion.technique(
            for: HomeSuggestion.goal(forHour: Calendar.current.component(.hour, from: .now)),
            techniques: techniques,
            history: journey.history
        )
        .map { DialStop.standingFor($0, dialled: dialled[$0.slug]) }
    }
}
