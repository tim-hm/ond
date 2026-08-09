import OndKit
import OndUI
import SwiftUI

/// Home as a dial: one recommended thing in focus, everything else a tick away.
///
/// The prototype of decision D9. It leads with what the routing layer chose —
/// the occasion that fits the hour, or the rung of Start here this person has
/// reached — and the dial is how you browse away from it. Recommendation is the
/// default and selection the fallback, which is what lets the screen hold one
/// thing at a time and still reach every exercise the app has.
///
/// It sits beside `HomeView` rather than replacing it, so the two can be felt
/// against each other before either is deleted. `HomeSurface` is the switch.
///
/// Everything on this screen was chosen against the alternative, on a phone.
/// The aperture beat a snapping column and a turning drum; an ordinary button
/// that does not move beat the orb and the accent cross-fade that came with it;
/// a sentence inside the window beat one under the dial, which read as belonging
/// to the stop below it. What the dial holds is the last of those: only the
/// routing layer's stops, because the catalogue is a whole tab two icons away
/// and nine rows duplicating it is how one screen came to hold four different
/// kinds of thing.
struct HomeDialView: View {
    let model: TechniqueListModel
    let routes: RoutesModel
    let sessions: any SessionRecording

    @Environment(SessionSettings.self) private var settings
    @Environment(SubscriptionStore.self) private var plus

    /// The dial as of the last rebuild. Held rather than recomputed in `body`
    /// because building it reads the clock, and a screen whose recommendation
    /// could change between two layout passes is not one anybody can reason
    /// about.
    @State private var dial: HomeDial?

    /// The stop in focus, and the only thing that says where the dial is. Nil
    /// only before the first build.
    @State private var focused: DialStop.ID?

    /// Recorded history, oldest first. Re-read after every session: one just
    /// finished changes both what to recommend and which rung of Start here
    /// this person has reached.
    @State private var history: [SessionRecord] = []

    @State private var started: StartedSession?
    @State private var isShowingPaywall = false

    var body: some View {
        content
            .paletteGround()
            // One task for all three reads, so leaving the screen cancels
            // whatever is still in flight, and all three started together
            // because none depends on another.
            //
            // Waited out rather than built twice. The routes decide which stop
            // leads, and replacing the whole stop list under a scroll view a
            // beat after it settled is how the dial arrived on an arbitrary
            // occasion instead of on the recommendation. Both fetches answer
            // inside `CachedTechniqueRepository`'s deadline whether or not
            // there is a network, so the wait this costs is bounded and the
            // screen holds one spinner rather than showing a dial that then
            // moves.
            .task {
                async let recorded = sessions.recordedSessions()
                async let routed: Void = routes.loadIfNeeded()
                await model.loadIfNeeded()
                await routed
                history = await recorded
                rebuild()
            }
            .paywall(highlighting: .plus, isPresented: $isShowingPaywall)
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

        // The dial arrives whole or not at all: it is not built until the routes
        // have resolved too, and drawing the picker and the button from a nil
        // dial in the meantime would be an empty screen wearing none of the
        // marks of one.
        case .loaded where dial == nil:
            ProgressView()

        case .loaded:
            loaded

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

    /// The dial, and the way to start what it is pointing at. Nothing else.
    private var loaded: some View {
        // Read once. The picker's stops and the identity derived from them have
        // to be the same list, and computing it twice is how they could stop
        // being.
        let stops = visible

        return VStack(spacing: 0) {
            Spacer(minLength: Theme.Spacing.loose)

            // The dial and its button are one block, centred together. Held
            // apart by a spacer each they drift to opposite ends of whatever
            // phone this is, and a screen holding two things at arm's length
            // reads as two screens.
            //
            // The gap between them is stated once, below the picker: the
            // aperture already reserves an empty slot on either side of the stop
            // in focus, so this is added to a third of a screen of air rather
            // than to nothing.
            VStack(spacing: 0) {
                DialPicker(
                    stops: stops,
                    focused: $focused,
                    tier: plus.tier,
                    ticks: settings.cueMode.playsHaptics
                )
                // The picker's identity, and the reason it is the stop ids
                // rather than a counter: a scroll view whose collection is
                // replaced under it re-lays out and writes its own idea of the
                // anchored item back through `scrollPosition(id:)`, which lands
                // on whatever happens to sit at the anchor and overwrites the
                // focus that was just set. The routes arrive a beat after the
                // catalogue and replace every stop, so that race is the normal
                // path, not an edge. Re-identifying the picker makes it a fresh
                // scroll view, which starts where the binding says.
                .id(stops.map(\.id))

                if let stop {
                    beginning(stop)
                        .padding(.top, Theme.Spacing.loose)
                }
            }

            Spacer(minLength: Theme.Spacing.loose)
        }
        .padding(.horizontal, Theme.Spacing.standard)
        .frame(maxWidth: .infinity)
    }

    /// How the focused stop is started — or why it cannot be started here.
    @ViewBuilder
    private func beginning(_ stop: DialStop) -> some View {
        switch stop.surface {
        case .fullScreen:
            BeginButton(
                technique: stop.technique,
                isLocked: !stop.technique.isUnlocked(for: plus.tier)
            ) {
                begin(stop)
            }

        case .discreet:
            onTheWrist
        }
    }

    /// What a discreet occasion offers instead of a begin button.
    ///
    /// A discreet session is one nobody watching would notice, and the phone
    /// cannot deliver that: the only surface that can is `OndWatch`, where
    /// `DiscreetSpikeView` taps the rhythm out with nothing on screen. Starting
    /// the full-screen session from here would keep the button and break the
    /// promise the word "quietly" just made, so the dial says where it lives
    /// instead. That is the honest shape of the distinction until the phone
    /// grows a discreet surface of its own.
    private var onTheWrist: some View {
        VStack(spacing: Theme.Spacing.close) {
            Image(systemName: "applewatch")
                .font(.system(size: 32))
                .foregroundStyle(Theme.Ink.secondary)

            Text("This one runs on your wrist — start it from the watch.")
                .font(.subheadline)
                .foregroundStyle(Theme.Ink.secondary)
                .multilineTextAlignment(.center)
        }
        .accessibilityElement(children: .combine)
    }

    /// The stops on the dial: what the routing layer put here, and nothing else.
    ///
    /// The catalogue is deliberately not among them. It is a whole tab two icons
    /// away, so nine rows repeating it here bought nothing but length — and the
    /// four kinds of thing that made this screen confusing to read. What is left
    /// is one kind, a reason to breathe now, which is why none of it needs a
    /// caption saying which kind.
    private var visible: [DialStop] {
        dial?.routed ?? []
    }

    /// The stop in focus, or nil before the first build.
    ///
    /// Resolved against the stops the dial actually draws rather than against
    /// every stop the model holds. Those two differ by the whole catalogue, and
    /// searching the wider list is how the button came to start an exercise no
    /// row on screen named. The fallback is the first stop, which `routed` keeps
    /// the lead at, and covers the instant between the dial being built and the
    /// focus settling onto it — so neither the sentence nor the button blanks.
    private var stop: DialStop? {
        let shown = visible
        return shown.first { $0.id == focused } ?? shown.first
    }

    /// Rebuilds the dial from whatever has landed, keeping the focus where the
    /// person left it.
    ///
    /// The recommendation may take the focus back only while nobody has moved
    /// it. That is what lets the routes land a second after the catalogue and
    /// still lead — and what stops a finished session, or a late fetch,
    /// snatching the dial away from somebody who has ticked somewhere.
    ///
    /// The third case is a focus with nowhere to stay, and it is asked of
    /// `routed` rather than of every stop: a device that reached the server for
    /// the first time between two builds had the whole catalogue on its dial and
    /// has it no longer, so a stop that still exists can still have stopped
    /// being drawn.
    private func rebuild() {
        guard case let .loaded(techniques) = model.state else { return }

        let settled = focused == nil || focused == dial?.lead?.id
        let built = HomeDial(
            techniques: techniques,
            routes: routes.available,
            history: history,
            hour: Calendar.current.component(.hour, from: .now),
            dialled: dialledBySlug(among: techniques)
        )
        dial = built

        if settled || !built.routed.contains(where: { $0.id == focused }) {
            focused = built.lead?.id
        }
    }

    /// What this person has dialled themselves, keyed by slug — so a stop can
    /// state the length the button beneath it will actually play.
    ///
    /// Folded here, once per rebuild, rather than asked per row: the settings
    /// are the app's and the dial is a value type, and a `HomeDial` that
    /// reached into a store would stop being testable at any time of day.
    private func dialledBySlug(among techniques: [Technique]) -> [String: TechniqueOverrides] {
        techniques.reduce(into: [:]) { dialled, technique in
            dialled[technique.slug] = settings.overrides(for: technique)
        }
    }

    /// Starts the focused stop, or opens the paywall where a subscription owns
    /// it.
    ///
    /// `stop.dose` is the whole of the decision — an occasion's prescription
    /// where there is one, this person's own dials otherwise — and reading it
    /// here rather than re-deciding is what keeps the length under the stop's
    /// name and the length actually played the same number.
    private func begin(_ stop: DialStop) {
        let start = SessionStart(sessions: sessions, settings: settings, tier: plus.tier)

        guard let model = start.session(for: stop.technique, dialledWith: stop.dose) else {
            isShowingPaywall = true
            return
        }

        started = StartedSession(model: model)
    }
}
