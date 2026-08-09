import OndKit
import OndStyle
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
/// What is deliberately unchanged from the screen it may replace: the orb is
/// the same control, the accent is the goal's, and beginning is still the only
/// committing action. The comparison is meant to be about the picker.
struct HomeDialView: View {
    let model: TechniqueListModel
    let routes: RoutesModel
    let sessions: any SessionRecording

    /// The aim the chrome tints the tab bar with — see `AppChrome`. Written
    /// from the focused stop, so ticking recolours the bar exactly as spinning
    /// the aim wheel does.
    @Binding var goal: TechniqueGoal?

    @Environment(SessionSettings.self) private var settings
    @Environment(SubscriptionStore.self) private var plus

    /// The dial as of the last rebuild. Held rather than recomputed in `body`
    /// because building it reads the clock, and a screen whose recommendation
    /// could change between two layout passes is not one anybody can reason
    /// about.
    @State private var dial: HomeDial?

    /// The stop in focus. Nil only before the first build.
    @State private var focused: DialStop.ID?

    /// Which set of stops the dial is currently showing, as a number that only
    /// goes up.
    ///
    /// The picker's identity. A scroll view whose collection is replaced under
    /// it re-lays out and writes its own idea of the anchored item back through
    /// `scrollPosition(id:)` — which lands on whatever happens to sit at the
    /// anchor and overwrites the focus that was just set. The routes arrive a
    /// beat after the catalogue and replace every stop, so that race is the
    /// normal path, not an edge: on arrival the dial settled onto an arbitrary
    /// occasion rather than onto the recommendation. Re-identifying the picker
    /// makes it a fresh scroll view, which starts where the binding says.
    @State private var generation = 0

    /// Which take on the dial is on screen. Prototype scaffolding — see
    /// `DialTreatment`.
    @State private var treatment: DialTreatment = .wheel

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
            .onChange(of: focused) { _, _ in
                syncGoal()
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
        // have resolved too, and drawing the band, the picker and the orb from
        // a nil dial in the meantime would be an empty screen wearing none of
        // the marks of one.
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

    /// The band name, the dial, the focused stop's own sentence, and the orb —
    /// in that order, because that is the order somebody reads them in: where
    /// am I, what is here, what is this, start it.
    private var loaded: some View {
        GeometryReader { proxy in
            let typeScale = min(max(proxy.size.width / 375, 1), 1.25)

            VStack(spacing: 0) {
                Spacer(minLength: Theme.Spacing.close)

                bandCaption

                DialPicker(
                    stops: dial?.stops ?? [],
                    focused: $focused,
                    treatment: treatment,
                    tier: plus.tier,
                    ticks: settings.cueMode.playsHaptics
                )
                .id(generation)

                sentence

                Spacer(minLength: Theme.Spacing.close)

                beginning(typeScale: typeScale)

                Spacer(minLength: Theme.Spacing.close)

                treatmentSwitch
            }
            .padding(.horizontal, Theme.Spacing.standard)
            .frame(maxWidth: .infinity)
        }
    }

    /// Which zone of the dial the focus is in, captioned rather than laid out —
    /// one stop is on screen at a time, so there is nowhere to put a heading
    /// above a group.
    private var bandCaption: some View {
        Text(stop?.band.title ?? "")
            .font(.footnote)
            .kerning(1.6)
            .foregroundStyle(Theme.Ink.tertiary)
            .frame(height: Theme.Spacing.loose)
            // The band is the one thing on this screen that changes without
            // the person's finger moving to it, so it fades rather than cuts.
            .animation(.easeOut(duration: 0.2), value: stop?.band)
    }

    /// The focused stop's own sentence: an occasion's promise, a step's reason
    /// for being where it is, or the exercise's summary.
    ///
    /// Below the dial rather than inside a row, because a row has to stay one
    /// line at every detent spacing and this is the payoff for having stopped
    /// here.
    private var sentence: some View {
        Text(stop?.detail ?? "")
            .font(.subheadline)
            .foregroundStyle(Theme.Ink.secondary)
            .multilineTextAlignment(.center)
            .lineLimit(2, reservesSpace: true)
            .padding(.top, Theme.Spacing.close)
    }

    /// How the focused stop is started — or why it cannot be started here.
    @ViewBuilder
    private func beginning(typeScale: CGFloat) -> some View {
        if let stop {
            switch stop.surface {
            case .fullScreen:
                OrbBeginButton(
                    technique: stop.technique,
                    isLocked: !stop.technique.isUnlocked(for: plus.tier),
                    typeScale: typeScale,
                    // Still. The dial is the thing that moves on this screen,
                    // and it moves only when a finger asks it to — an orb
                    // breathing on its own beside it is a second ambience
                    // competing for the same glance.
                    breathes: false
                ) {
                    begin(stop)
                }

            case .discreet:
                onTheWrist
            }
        }
    }

    /// What a discreet occasion offers instead of the orb.
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

    /// The three takes, switchable in place. Prototype scaffolding: it goes
    /// when two of the treatments do.
    private var treatmentSwitch: some View {
        HStack(spacing: Theme.Spacing.standard) {
            ForEach(DialTreatment.allCases) { candidate in
                Button(candidate.title) {
                    treatment = candidate
                }
                .buttonStyle(.plain)
                .font(.caption)
                .foregroundStyle(
                    candidate == treatment ? Theme.Accent.brand : Theme.Ink.tertiary
                )
                .accessibilityAddTraits(candidate == treatment ? [.isSelected] : [])
            }
        }
        .padding(.bottom, Theme.Spacing.close)
    }

    /// The stop in focus, or nil before the first build. Falls back to the lead
    /// for the instant between the dial being built and the focus settling onto
    /// it, so the sentence and the orb never blank.
    private var stop: DialStop? {
        guard let dial else { return nil }
        return dial.stops.first { $0.id == focused } ?? dial.lead
    }

    /// Rebuilds the dial from whatever has landed, keeping the focus where the
    /// person left it.
    ///
    /// The recommendation may take the focus back only while nobody has moved
    /// it. That is what lets the routes land a second after the catalogue and
    /// still lead — and what stops a finished session, or a late fetch,
    /// snatching the dial away from somebody who has ticked somewhere. The
    /// third case is a focus whose stop no longer exists, which has nowhere to
    /// stay.
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

        // Compared before the assignment and only on the ids, so a rebuild that
        // reaches the same stops leaves the picker — and any scroll in flight —
        // alone.
        if built.stops.map(\.id) != dial?.stops.map(\.id) {
            generation += 1
        }
        dial = built

        if settled || !built.stops.contains(where: { $0.id == focused }) {
            focused = built.lead?.id
        }
    }

    /// What this person has dialled themselves, keyed by slug — so a stop can
    /// state the length the orb beneath it will actually play.
    ///
    /// Folded here, once per rebuild, rather than asked per row: the settings
    /// are the app's and the dial is a value type, and a `HomeDial` that
    /// reached into a store would stop being testable at any time of day.
    private func dialledBySlug(among techniques: [Technique]) -> [String: TechniqueOverrides] {
        techniques.reduce(into: [:]) { dialled, technique in
            dialled[technique.slug] = settings.overrides(for: technique)
        }
    }

    /// Points the chrome's aim at the focused stop.
    ///
    /// Written only on a change. The aim lives on the tab view, so an
    /// idempotent assignment here invalidates — and re-tints — the whole of the
    /// chrome for a colour that did not move, which is the same trap
    /// `HomeView.settleGoal()` documents.
    private func syncGoal() {
        let next = stop?.goal
        if next != goal {
            goal = next
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
