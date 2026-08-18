import OndKit
import OndUI
import SwiftUI

/// Home: how the practice stands and what to breathe next.
///
/// Everything here is either useful now or starts in one tap. The wordmark
/// leads, one plain-language line says where the week stands, the continue
/// card holds the single next breath, and the practices card keeps the stops
/// this person chose to keep near. The settled shape belongs to Progress.
///
/// It scrolls under its own masthead rather than a navigation title: the
/// wordmark row is page content — the spec's Home opens with the app's name,
/// not a section heading — so the system bar is hidden here and Settings
/// reaches this screen through the overflow button instead of a gear in
/// chrome this screen no longer draws.
///
/// **What to offer is `HomeShelf`'s, not this file's.** The continue card
/// leads with the last run where one still resolves and the hour's suggestion
/// otherwise — the eyebrow states which — and the practices card omits
/// whatever that card already took. That split keeps the rules under test,
/// since the app target has no bundle to put one in.
struct HomeView: View {
    let catalogue: TechniqueListModel
    let occasions: OccasionCatalogueModel
    let sessions: any SessionRecording

    /// The exercises this person composed, so a star on one resolves to a row —
    /// and so the Progress chart counts them. Beside the catalogue rather than
    /// folded into it, for the reason `AppRoots` keeps them apart: two services,
    /// two loads, and only one of them needs an identity.
    let own: UserTechniqueModel

    /// The history behind the continue card and the state line.
    let journey: JourneyModel

    /// Read by Settings, which remains reachable from Home's overflow.
    let profiles: ProfileStore

    /// What the "All exercises" row does. A closure handed down from the
    /// chrome rather than a navigation push, because the destination is the
    /// Exercises *tab* — pushing a copy of that root inside Home's stack
    /// would leave two of the same screen alive with separate scroll state.
    let openExercises: () -> Void

    /// Read by the rows for the lengths they print, and by the fold in
    /// `HomeView+Folding` for the lengths it bakes into a stop — which is why
    /// these three are not `private`.
    @Environment(SessionSettings.self) var settings
    @Environment(SubscriptionStore.self) private var plus

    /// The stars. In the environment beside the other two rather than passed
    /// in, because it is the install's and outlives this screen — and because
    /// the deletion list in `OndApp` is what has to reach it, not `AppRoots`.
    @Environment(StarredStopStore.self) var stars

    /// The watch-trends summary, read here for the one card Home may show of
    /// it. In the environment for `HealthTrendsCard`'s reason: it is the
    /// install's, shared with the coach and the check-ins screen.
    @Environment(HealthContextModel.self) private var heart

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

    /// Whether the overflow's Settings item has been taken. A flag plus
    /// `navigationDestination` rather than a `NavigationLink`, because a link
    /// inside a `Menu` is a row the system draws but does not push.
    @State private var isShowingSettings = false

    init(
        catalogue: TechniqueListModel,
        occasions: OccasionCatalogueModel,
        sessions: any SessionRecording,
        own: UserTechniqueModel,
        journey: JourneyModel,
        profiles: ProfileStore,
        openExercises: @escaping () -> Void
    ) {
        self.catalogue = catalogue
        self.occasions = occasions
        self.sessions = sessions
        self.own = own
        self.journey = journey
        self.profiles = profiles
        self.openExercises = openExercises
        _launcher = State(wrappedValue: StopLauncher(sessions: sessions))
    }

    var body: some View {
        NavigationStack {
            content
                .paletteGround()
                .toolbar(.hidden, for: .navigationBar)
                .navigationDestination(isPresented: $isShowingSettings) {
                    SettingsView(catalogue: catalogue, profiles: profiles)
                }
                .stopLauncher(launcher)
        }
        // The local read first, so the numbers are complete before anything
        // touches the network; the two fetches then run behind what is already
        // drawn. Nothing here folds — the triggers below do, because every one
        // of these lands as a change to something they watch.
        .task {
            await journey.refresh()

            async let occasionsLoaded: Void = occasions.loadIfNeeded()
            await catalogue.loadIfNeeded()
            await occasionsLoaded

            await journey.sync()
        }
        // Separate from the catalogue's load rather than sequenced after it, the
        // same way the Exercises tab does it: two services, and eleven curated
        // exercises should not wait on somebody's own.
        .task { await own.loadIfNeeded() }
        // The read the trends card's visibility turns on — the card cannot run
        // it itself, because it is only mounted once readings exist. Ungated:
        // "no read happens below the tier" is the model's own property, and
        // keying on the tier re-runs the read when it changes either way —
        // buying önd+ in place fills the card, a lapse blanks it.
        .task(id: plus.tier) {
            await heart.loadHealthTrends()
        }
        // The heart card's read. Keyed on all three things that change what it
        // should draw: the tier, the opt-in — this screen is where somebody
        // lands after granting it in Settings, and nothing else would re-run
        // the read — and the sessions themselves, by id, so a deletion or a
        // restore moves the key even when the newest session has not changed.
        // The model's own freshness window is what keeps a tab hop from
        // re-reading.
        .task(id: HeartRead(
            tier: plus.tier,
            readsHealth: heart.coachReadsHealthTrends,
            sessions: journey.history.map(\.id)
        )) {
            await heart.loadPracticeHeart(from: journey.history)
        }
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
        .onChange(of: occasions.available) { _, _ in foldShelf() }
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

    /// Both loads, because the occasions are what turn half of this screen from
    /// exercises into protocols — and a person who has just watched one fail has
    /// no way to tell which of the two it was.
    private func retryReferenceData() {
        Task {
            async let occasionsLoaded: Void = occasions.refresh()
            await catalogue.refresh()
            await occasionsLoaded
        }
    }

    private var scroll: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.loose) {
                masthead

                // On the minute tick the old grid used for its relative
                // times: the line is time-derived, and a week boundary can
                // pass while Home sits on screen with nothing else changing.
                TimelineView(.periodic(from: .now, by: 60)) { context in
                    Text(HomeStateLine.line(history: journey.history, now: context.date))
                        .font(.callout)
                        .foregroundStyle(Theme.Ink.secondary)
                        .accessibilityIdentifier("home-state-line")
                }

                if let lead = shelf?.lead {
                    ContinueCard(lead: lead, tier: plus.tier) {
                        launcher.begin(lead.stop)
                    }
                }

                practices
                trends
                practiceHeart
            }
            .padding(Theme.Spacing.standard)
        }
    }

    /// The wordmark and the way to everything that is not practice.
    private var masthead: some View {
        HStack(spacing: Theme.Spacing.close) {
            HStack(alignment: .firstTextBaseline, spacing: Theme.Spacing.close) {
                // Lowercase, and never uppercased: the name is önd, and ÖND is
                // a different word wearing its hat.
                Text("önd")
                    .displaySerif(size: 40)
                    .foregroundStyle(Theme.Ink.primary)

                Text("breathe")
                    .font(.title2)
                    .foregroundStyle(Theme.Ink.secondary)
            }
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isHeader)

            Spacer(minLength: Theme.Spacing.close)

            overflow
        }
    }

    /// The screen's one door away from practice. A menu rather than a bare
    /// gear so the row stays a wordmark with a single quiet control on it, and
    /// whatever else must one day leave Home has somewhere to arrive without
    /// the masthead growing a button per destination.
    private var overflow: some View {
        Menu {
            Button("Settings", systemImage: "gearshape") {
                isShowingSettings = true
            }
        } label: {
            Image(systemName: "ellipsis")
                .font(.body.weight(.semibold))
                .foregroundStyle(Theme.Ink.primary)
                .frame(width: 36, height: 36)
                .glassEffect(.regular.interactive(), in: .circle)
                // Inside the label, where the hit area actually lives — a
                // frame on the Menu itself would leave taps in the outer ring
                // answering to nothing. `StopStarButton` makes the same move.
                .frame(width: Theme.Metrics.minimumTapTarget)
                .tapTarget()
        }
        .accessibilityLabel("More")
    }

    /// What there is to breathe under the lead — what this person starred, then
    /// the catalogue behind it — and the road to the rest.
    ///
    /// No empty state, because there is no empty case: `HomeShelf.practices`
    /// tops the stars up from the catalogue, so the card is a shelf on the first
    /// launch and a shelf after fifty. The sentence about starring that used to
    /// stand here explained a feature to somebody who had come to breathe; what
    /// a star does is visible enough in the filled star on a row that has moved
    /// to the top. It still waits for the fold — `shelf` is nil until then.
    @ViewBuilder
    private var practices: some View {
        if let shelf {
            LabelledSection(title: "Practices") {
                PracticesCard(
                    practices: shelf.practices,
                    tier: plus.tier,
                    start: { launcher.begin($0) },
                    openExercises: openExercises
                )
            }
        }
    }

    /// The watch-trends card, only where there is something true to show: the
    /// tier includes it *and* the read yielded readings. Both conditions,
    /// deliberately — `.trends` can outlive a lapsed tier for the length of
    /// the corrective re-read, and the card switches on the tier itself, so
    /// state alone would let it mount mid-lapse and render its locked upsell
    /// here. No locked teaser — Home is what the practice offers, and an
    /// upsell wearing a card's clothes would put the boundary önd+ promises
    /// to keep on the one screen everybody starts at. The offer lives with
    /// the check-ins, where the data would appear.
    @ViewBuilder
    private var trends: some View {
        if plus.tier >= .healthTrends, case .trends = heart.healthTrends {
            HealthTrendsCard(health: heart)
        }
    }

    /// The heart card, only where there is something true to draw.
    ///
    /// Both conditions on `trends`' reasoning, and one more of its own: the
    /// heartline is nil for every silence there is — not read, not allowed, no
    /// watch on a wrist, too few readings to mean anything — so there is no
    /// empty state and no locked teaser. A card about a person's heartbeat is
    /// the last place önd should advertise a subscription.
    @ViewBuilder
    private var practiceHeart: some View {
        if plus.tier >= .healthTrends, let heartline = heart.practiceHeart {
            PracticeHeartCard(heartline: heartline)
        }
    }
}

/// What has to change before the heart around your practice is read again.
///
/// A named value rather than a tuple, because `task(id:)` wants one `Equatable`
/// value and a tuple is not one. The sessions arrive as ids rather than as the
/// records: the whole history compares every field of every session on each
/// pass, and what this asks is only whether the set of practices moved.
private struct HeartRead: Equatable {
    let tier: SubscriptionTier
    let readsHealth: Bool
    let sessions: [UUID]
}
