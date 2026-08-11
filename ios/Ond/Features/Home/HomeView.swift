import OndKit
import OndUI
import SwiftUI

/// Home: a shortlist of what to breathe now, and a board of everything else on offer.
///
/// Decision D9, and the whole of Breathe. It leads with what the routing layer chose
/// — the occasion that fits the hour, or the rung of Start here this person has
/// reached — and the board is how you browse away from it. Recommendation is the
/// default and selection the fallback, which is what lets the screen hold one clear
/// offer and still reach every exercise home routes to.
///
/// The drawing is `HomeTilesView`'s; this owns the decisions. What the clock and the
/// history choose, what a star does to that order, and what happens when somebody
/// commits — the paywall, the discreet occasion the phone cannot honour, the session
/// itself — all resolve here, because they are the screen's rules rather than any
/// layout's. That split is what let six other layouts be tried against these same
/// rules and thrown away without touching them.
///
/// One thing carries over from those experiments as a hard constraint: **nothing on
/// this screen may be a vertical scroll view.** A large navigation title collapses
/// against the nearest one, so a scrolling home screen loses the title the other three
/// tab roots have — and loses it *inconsistently*, depending on where the scroll
/// happened to open. The board pages horizontally for exactly this reason.
struct HomeView: View {
    let model: TechniqueListModel
    let routes: RoutesModel
    let sessions: any SessionRecording

    /// The exercises this person composed, so home's `yours` band has something in
    /// it. Beside the catalogue rather than folded into it, for the reason `AppRoots`
    /// keeps them apart: two services, two loads, and only one of them needs an
    /// identity.
    let own: UserTechniqueModel

    @Environment(SessionSettings.self) private var settings
    @Environment(SubscriptionStore.self) private var plus

    /// The cards this person starred. In the environment beside the other two rather
    /// than passed in, because it is the install's and outlives this screen — and
    /// because the deletion list in `OndApp` is what has to reach it, not `AppRoots`.
    @Environment(StarredStopStore.self) private var stars

    /// What home offers as of the last rebuild. Held rather than recomputed in `body`
    /// because building it reads the clock, and a screen whose recommendation could
    /// change between two layout passes is not one anybody can reason about.
    @State private var dial: HomeDial?

    /// Recorded history, oldest first. Re-read after every session: one just finished
    /// changes both what to recommend and which rung of Start here this person has
    /// reached.
    @State private var history: [SessionRecord] = []

    @State private var started: StartedSession?
    @State private var isShowingPaywall = false

    /// The occasion somebody tapped that only the watch can deliver, if any.
    @State private var wristbound: DialStop?

    var body: some View {
        NavigationStack {
            content
                .paletteGround()
                .navigationTitle("Breathe")
        }
        // One task for all three reads, so leaving the screen cancels whatever is
        // still in flight, and all three start together because none depends on
        // another.
        //
        // Waited out rather than built twice: the routes decide which stop leads, and
        // replacing the whole list a beat after it settled is how home arrived on an
        // arbitrary occasion instead of on the recommendation. Both fetches answer
        // inside `CachedTechniqueRepository`'s deadline, so the wait is bounded and the
        // screen holds one spinner rather than a board that rearranges itself.
        .task {
            async let recorded = sessions.recordedSessions()
            async let routed: Void = routes.loadIfNeeded()
            await model.loadIfNeeded()
            await routed
            history = await recorded
            rebuild()
        }
        // Separate from the catalogue's load rather than sequenced after it, the same
        // way the Exercises tab does it: two services, and nine curated exercises
        // should not wait on somebody's own. The rebuild is what folds them in once
        // they land, so home gains its `yours` band a beat after the rest rather than
        // holding the screen for it.
        .task {
            await own.loadIfNeeded()
            rebuild()
        }
        // The authored list changes on another tab: somebody writes an exercise in the
        // composer, which stars it so home leads with it. This screen's tasks ran long
        // before that, and a tab root is not torn down when you leave it — so without
        // this the star pins a card home has never built, and the exercise nobody can
        // see turns up on the next launch instead.
        .onChange(of: own.techniques.map(\.id)) { _, _ in rebuild() }
        // A star made on an exercise's own screen has to reach the board, and that
        // tap happens on another tab — the same reason the authored list is watched
        // above. The board's own stars come through here too rather than dealing
        // themselves, so a star cannot mean two things depending on which screen
        // made it.
        .onChange(of: stars.starred) { _, _ in
            if let dial {
                deal(from: dial)
            }
        }
        .paywall(highlighting: .plus, isPresented: $isShowingPaywall)
        .alert(
            "This one runs on your wrist",
            isPresented: Binding { wristbound != nil } set: { showing in
                if !showing {
                    wristbound = nil
                }
            },
            presenting: wristbound
        ) { _ in
            Button("OK", role: .cancel) {}
        } message: { stop in
            Text(
                "\(stop.title) is meant to go unnoticed — no screen, just the rhythm tapped out. Start it from OndWatch."
            )
        }
        .fullScreenCover(item: $started) {
            Task {
                history = await sessions.recordedSessions()
                rebuild()
            }
        } content: { session in
            SessionView(model: session.model)
        }
    }

    @ViewBuilder
    private var content: some View {
        switch model.state {
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

        // Home arrives whole or not at all: it is not built until the routes have
        // resolved too, and drawing a board from a nil dial in the meantime would be
        // an empty screen wearing none of the marks of one.
        case .loaded where dial == nil:
            ProgressView()

        case .loaded:
            board

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

    private var retryButton: some View {
        Button("Try again") {
            Task {
                await model.load()
                await routes.load()
                rebuild()
            }
        }
    }

    private var board: some View {
        VStack(spacing: 0) {
            Spacer(minLength: Theme.Spacing.loose)

            HomeTilesView(
                cards: cards,
                tier: plus.tier,
                ticks: settings.cueMode.playsHaptics,
                starred: stars.starred,
                // The re-deal is the `onChange` above's, not this closure's: the
                // board is state now, and a star that moved a card without redealing
                // would fill its own glyph and leave the card where it was.
                star: { stars.toggle($0.id) },
                start: begin
            )

            Spacer(minLength: Theme.Spacing.loose)
        }
        .frame(maxWidth: .infinity)
    }

    /// The cards, in the order `HomeDeck` decides: the hour's suggestion, then the
    /// stars, then what has been breathed lately and often, then the rest.
    ///
    /// Held rather than computed, which is `dial`'s argument one step further along:
    /// building a deck walks the whole recorded history twice and allocates a card
    /// per stop, and as a computed property it did that on every body pass — every
    /// star tap, every page turn, every tier or cue change — over a history that
    /// only ever grows. It is the one cost on this screen that gets worse the more
    /// somebody uses the app.
    @State private var cards: [HomeDeck.Card] = []

    /// Rebuilds home from whatever has landed.
    ///
    /// `routed(starring:)` rather than every stop: the catalogue is a whole tab two
    /// icons away, a board repeating it would be the Exercises tab with rounded
    /// corners, and a star is how one of its entries says otherwise.
    private func rebuild() {
        guard case let .loaded(techniques) = model.state else { return }

        let dial = HomeDial(
            techniques: techniques,
            routes: routes.available,
            history: history,
            hour: Calendar.current.component(.hour, from: .now),
            dialled: dialledBySlug(among: techniques),
            authored: own.techniques
        )

        self.dial = dial
        deal(from: dial)
    }

    /// Deals the board from a dial that is already built.
    ///
    /// Separate from `rebuild` because a star changes which stops home offers and
    /// the order it offers them in, without changing anything the dial *reads*: the
    /// hour is the same, the history is the same, and re-routing the whole catalogue
    /// to answer a tap would be the expensive half of the work for none of the reason.
    ///
    /// The same set twice, on purpose — once to decide membership, once to decide
    /// order.
    private func deal(from dial: HomeDial) {
        cards = HomeDeck(
            stops: dial.routed(starring: stars.starred),
            history: history,
            starred: stars.starred
        ).cards
    }

    /// What this person has dialled themselves, keyed by slug — so a card can state
    /// the length the session it starts will actually play.
    ///
    /// Folded here, once per rebuild, rather than asked per card: the settings are the
    /// app's and `HomeDial` is a value type, and one that reached into a store would
    /// stop being testable at any time of day.
    private func dialledBySlug(among techniques: [Technique]) -> [String: TechniqueOverrides] {
        techniques.reduce(into: [:]) { dialled, technique in
            dialled[technique.slug] = settings.overrides(for: technique)
        }
    }

    /// Starts a card, or says why it cannot be started here.
    ///
    /// The one funnel every layout commits through, which is why both refusals live
    /// here rather than on a card. A discreet occasion is the subtler of the two: the
    /// promise the word makes is one only `OndWatch` can keep — `DiscreetSpikeView`
    /// taps the rhythm out with nothing on screen — and starting the full-screen
    /// session from here would break it while looking like success. It stays on the
    /// board rather than being filtered out, because a person who cannot see the
    /// feature cannot know their watch has it.
    ///
    /// `stop.dose` is the whole of the length decision — an occasion's prescription
    /// where there is one, this person's own dials otherwise — and reading it here
    /// rather than re-deciding is what keeps the length printed on the card and the
    /// length actually played the same number.
    private func begin(_ stop: DialStop) {
        guard stop.surface == .fullScreen else {
            wristbound = stop
            return
        }

        let start = SessionStart(sessions: sessions, settings: settings, tier: plus.tier)

        guard let model = start.session(for: stop.technique, dialledWith: stop.dose) else {
            isShowingPaywall = true
            return
        }

        started = StartedSession(model: model)
    }
}
