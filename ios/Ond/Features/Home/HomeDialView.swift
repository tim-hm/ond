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
/// The second round. The aperture won and is now the only picker; the orb and
/// its accent cross-fade are gone, replaced by an ordinary button that does not
/// move until it is pressed. What is left open is what the dial holds and where
/// the focused stop's sentence lives, and those are `HomeDialOption`'s two
/// questions — which is the whole of what this screen still varies.
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

    /// The stop in focus, and the only thing that says where the dial is: in
    /// `sets` the shown band is read back off it, so there is one source of
    /// truth for the position rather than two that can disagree.
    @State private var focused: DialStop.ID?

    /// Which take is on screen. Prototype scaffolding — see `HomeDialOption`.
    @State private var option: HomeDialOption = .few

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
            // A take that holds fewer stops can leave the focus on one it does
            // not show, which is a dial pointing at nothing.
            .onChange(of: option) { _, _ in
                if !visible.contains(where: { $0.id == focused }) {
                    focused = visible.first?.id
                }
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

    /// The dial and the way to start what it is pointing at — and, in `sets`,
    /// the row of words naming which set is on the dial.
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
            // Gapless above the picker and spaced below it, because the aperture
            // already reserves an empty slot over the stop in focus: a gap
            // stated here as well would leave the set names floating a third of
            // a screen clear of the dial they name.
            VStack(spacing: 0) {
                if option.contents == .sets {
                    setSwitch
                }

                DialPicker(
                    stops: stops,
                    focused: $focused,
                    explains: option.explanation == .inWindow,
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
                // scroll view, which starts where the binding says — and tying
                // that to the ids means every change of what is shown gets it,
                // including switching sets.
                .id(stops.map(\.id))

                if let stop {
                    beginning(stop)
                        .padding(.top, Theme.Spacing.loose)
                }
            }

            Spacer(minLength: Theme.Spacing.loose)

            PrototypeSwitch(chosen: $option)
                .padding(.bottom, Theme.Spacing.close)
        }
        .padding(.horizontal, Theme.Spacing.standard)
        .frame(maxWidth: .infinity)
    }

    /// Which set the dial holds, in the take that keeps all three.
    ///
    /// A row that sits still while the dial moves, which is the whole of the
    /// difference from the caption it replaces: that one changed under the
    /// reader as they ticked across a boundary, so the ground moved with them.
    /// Tapping a word is a jump to the front of that set rather than a filter
    /// applied to a position — there is no state here beyond the focus.
    private var setSwitch: some View {
        HStack(spacing: Theme.Spacing.loose) {
            ForEach(bands, id: \.self) { band in
                Button(band.title) {
                    focused = dial?.stops.first { $0.band == band }?.id
                }
                .buttonStyle(.plain)
                .font(.footnote)
                .kerning(1.2)
                .foregroundStyle(band == shown ? Theme.Ink.primary : Theme.Ink.tertiary)
                .accessibilityAddTraits(band == shown ? [.isSelected] : [])
            }
        }
    }

    /// How the focused stop is started — or why it cannot be started here — with
    /// its own sentence above where the take puts it there.
    ///
    /// The sentence and the control are one block, closer to each other than
    /// either is to the dial, so what the words describe is the thing that is
    /// about to happen rather than whichever row they happen to sit under.
    private func beginning(_ stop: DialStop) -> some View {
        VStack(spacing: Theme.Spacing.close) {
            if option.explanation == .onBegin {
                Text(stop.detail)
                    .font(.subheadline)
                    .foregroundStyle(Theme.Ink.secondary)
                    .multilineTextAlignment(.center)
                    .lineLimit(2, reservesSpace: true)
            }

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

    /// The stops the dial is currently holding.
    ///
    /// Where the two takes differ. `reasons` leaves the catalogue to the
    /// Exercises tab and keeps only what the routing layer put here, so every
    /// stop is the same kind of thing — a reason to breathe now — and none of
    /// them needs a caption saying which kind. `sets` keeps all three and shows
    /// one at a time.
    private var visible: [DialStop] {
        guard let dial else { return [] }

        return switch option.contents {
        case .reasons: dial.routed
        case .sets: dial.stops.filter { $0.band == shown }
        }
    }

    /// The bands with something in them, in tick order. A set with no stops is
    /// not offered: a device that never reached the server has no occasions and
    /// no progression, and a word that leads to an empty dial is worse than one
    /// absence nobody notices.
    private var bands: [DialBand] {
        DialBand.allCases.filter { band in
            dial?.stops.contains { $0.band == band } ?? false
        }
    }

    /// Which set the focus is in. Derived rather than stored, so tapping a word
    /// and ticking past a boundary are the same event — a change of focus — and
    /// there is no second value to keep in step with it.
    private var shown: DialBand {
        stop?.band ?? .occasions
    }

    /// The stop in focus, or nil before the first build. Falls back to the lead
    /// for the instant between the dial being built and the focus settling onto
    /// it, so neither the sentence nor the button blanks.
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
        dial = built

        if settled || !built.stops.contains(where: { $0.id == focused }) {
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
