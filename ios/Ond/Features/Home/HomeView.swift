import OndKit
import OndStyle
import OndUI
import SwiftUI

/// Home: the breath at rest, one true sentence, and one button. The orb
/// breathes at Coherent pace whatever the button will start — an orb following
/// a three-a-minute exercise reads as a stall. What to offer is `HomeOffer`'s,
/// not this file's, so the rules stay under test. The offer is computed, not
/// held: every input it reads is observed, so a change two tabs away re-draws it.
struct HomeView: View {
    let catalogue: TechniqueListModel
    let occasions: OccasionCatalogueModel
    let sessions: any SessionRecording

    /// The exercises this person composed, so a choice or a star on one
    /// resolves to a row. Beside the catalogue rather than folded into it, for
    /// the reason `AppRoots` keeps them apart: two services, two loads, and
    /// only one of them needs an identity.
    let own: UserTechniqueModel

    /// The history behind the sentence.
    let journey: JourneyModel

    /// Read by Settings, and for the onboarding goals the default follows
    /// before anybody has chosen.
    let profiles: ProfileStore

    /// What the sheet's "All exercises" row does. A closure handed down from
    /// the chrome rather than a navigation push, because the destination is the
    /// Exercises *tab* — pushing a copy of that root inside Home's stack would
    /// leave two of the same screen alive with separate scroll state.
    let openExercises: () -> Void

    @Environment(SessionSettings.self) private var settings
    @Environment(SubscriptionStore.self) private var plus
    @Environment(StarredStopStore.self) private var stars
    @Environment(HomeChoiceStore.self) private var choice
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase

    @State private var launcher: StopLauncher

    /// Whether the gear has been taken. A flag plus `navigationDestination`
    /// rather than a `NavigationLink`, so Settings pushes onto this stack the
    /// way it always has while the gear stays a plain button.
    @State private var isShowingSettings = false

    /// Whether the sheet under the line is up.
    @State private var isChoosing = false

    /// Whether Home is the tab on screen. A tab root stays mounted while
    /// another tab is selected, and nothing promises a `TimelineView` stops
    /// for a view that is merely hidden — so the orb's clock reads this.
    @State private var isOnScreen = false

    /// Whether the sheet's "All exercises" row was taken. The tab switch waits
    /// for the dismissal rather than racing it: moving the selection under a
    /// live presentation is the one order SwiftUI does not promise to honour.
    @State private var isLeavingForExercises = false

    /// The orb's side. The spec's resting orb, with the outer ring standing
    /// well clear of the core — the card's inner ring sits too close to read
    /// as a breath's reach.
    private static let orbSide: CGFloat = 230

    /// Where the resting breath is held under Reduce Motion: a quarter of the
    /// way round, which is half full — a breath mid-way rather than the empty
    /// lungs the clock's zero would draw.
    private static let stillInstant = AmbientBreath.restingCycle / 4

    /// The gap between the button and its line: the spec's own number, so the
    /// two read as one control rather than as a button and a caption. Off the
    /// four-point rhythm on `Theme.Spacing.page`'s terms.
    private static let lineGap: CGFloat = 6

    /// The widest the one sentence draws. The spec's number: narrower than
    /// the page, so the line wraps instead of running the full width above a
    /// centred button.
    private static let sentenceWidth: CGFloat = 310

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
                // On the stack rather than on the loaded screen, so a catalogue
                // refresh mid-choice cannot tear the presentation down under
                // the finger and leave the flag set with nothing shown.
                .sheet(isPresented: $isChoosing, onDismiss: leaveIfAsked) {
                    if let offer {
                        HomeChoiceSheet(offer: offer) {
                            isLeavingForExercises = true
                            isChoosing = false
                        }
                    }
                }
        }
        // The local read first, so the sentence is complete before anything
        // touches the network; the fetches then run behind what is already
        // drawn. The occasions are loaded here even though Home no longer
        // offers a moment, because this is the tab every launch lands on and
        // Moments should arrive warm.
        .task {
            await journey.refresh()

            async let occasionsLoaded: Void = occasions.loadIfNeeded()
            await catalogue.loadIfNeeded()
            await occasionsLoaded

            await journey.sync()
        }
        // Separate from the catalogue's load rather than sequenced after it, the
        // same way the Exercises tab does it: two services, and thirteen curated
        // exercises should not wait on somebody's own.
        .task { await own.loadIfNeeded() }
        .onAppear { isOnScreen = true }
        .onDisappear { isOnScreen = false }
    }

    /// Home arrives whole or not at all: the button resolves a slug against
    /// the catalogue, so there is nothing to draw until that has landed — and
    /// something to say when it never does.
    @ViewBuilder
    private var content: some View {
        switch catalogue.state {
        case .loading:
            ReferenceLoadingView()

        case .loaded:
            if let offer {
                screen(offer)
            } else {
                EmptyCatalogueView(retry: retryReferenceData)
            }

        case let .failed(message):
            ReferenceRetryView(
                title: "Can't reach the catalogue",
                message: message,
                retry: retryReferenceData
            )
        }
    }

    /// Both loads, because a person who has just watched one fail has no way to
    /// tell which of the two it was.
    private func retryReferenceData() {
        Task {
            async let occasionsLoaded: Void = occasions.refresh()
            await catalogue.refresh()
            await occasionsLoaded
        }
    }

    /// What Home offers, or nil until the catalogue has landed — and nil for
    /// an empty one, which is what `EmptyCatalogueView` is for.
    private var offer: HomeOffer? {
        guard case let .loaded(techniques) = catalogue.state else { return nil }
        return HomeOffer(
            techniques: techniques,
            authored: own.techniques,
            starred: stars.starred,
            goals: profiles.profile.goals,
            choice: choice.choice,
            dialled: settings.overridesBySlug
        )
    }

    /// A scroller rather than a fixed column, though nothing here is meant to
    /// scroll: at accessibility sizes the orb, the sentence and the two
    /// controls outgrow the screen, and a column that cannot scroll clips the
    /// wordmark instead. `centredInScroller` keeps the resting layout centred
    /// until that happens.
    private func screen(_ offer: HomeOffer) -> some View {
        ScrollView {
            column(offer)
                .padding(.horizontal, Theme.Spacing.page)
                .padding(.vertical, Theme.Spacing.standard)
                .centredInScroller()
        }
        .scrollBounceBehavior(.basedOnSize)
    }

    private func column(_ offer: HomeOffer) -> some View {
        VStack(spacing: 0) {
            masthead

            Spacer(minLength: Theme.Spacing.standard)

            orb

            // Fixed rather than a third spacer, so the sentence reads as the
            // orb's caption and the two sit together above the button.
            sentence
                .padding(.top, Theme.Spacing.loose * 2)

            Spacer(minLength: Theme.Spacing.standard)

            Button("Breathe") {
                launcher.begin(offer.lead)
            }
            .buttonStyle(.inkAction(minHeight: Theme.Metrics.leadActionHeight))
            .accessibilityLabel("Breathe, \(offer.lead.spokenLabel(for: plus.tier))")
            .accessibilityHint("Starts the session")
            .accessibilityIdentifier("home-breathe")

            startWith(offer.lead)
                .padding(.top, Self.lineGap)
        }
    }

    /// The wordmark and the one way to everything that is not practice.
    private var masthead: some View {
        HStack(spacing: Theme.Spacing.close) {
            Wordmark(size: 30)

            Spacer(minLength: Theme.Spacing.close)

            Button {
                isShowingSettings = true
            } label: {
                // `title2` rather than a fixed 22 points: it is the spec's
                // size at the default setting and still grows with the type.
                Image(systemName: "gearshape")
                    .font(.title2)
                    .foregroundStyle(Theme.Ink.tertiary)
                    // Inside the label, where the hit area actually lives — a
                    // frame on the button itself would leave taps in the outer
                    // ring answering to nothing. `StopStarButton` makes the
                    // same move.
                    .frame(width: Theme.Metrics.minimumTapTarget)
                    .tapTarget()
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Settings")
        }
    }

    /// The breath at rest: the shared geometry at Coherent pace on the
    /// module's one resting clock, paused wherever motion is unwanted or
    /// unseen. Reduce Motion holds the reference instant so the still frame is
    /// a breath mid-way rather than an emptied one. Not a button — the capsule
    /// below is — and hidden from the assistive layer, which has the button's label.
    private var orb: some View {
        TimelineView(.animation(
            minimumInterval: Theme.Motion.restfulFrameInterval,
            paused: reduceMotion || !isBreathing
        )) { context in
            BreathGlyph(
                side: Self.orbSide,
                pose: .resting(
                    at: reduceMotion ? Self.stillInstant : context.date
                        .timeIntervalSinceReferenceDate
                ),
                layers: [.halo, .outerRing, .core],
                strength: .home
            )
        }
    }

    /// Where the week stands, or nothing at all. On the minute tick, because
    /// the line is time-derived and a week boundary can pass while Home sits
    /// on screen with nothing else changing. Serif, on `HomeStateLine`'s
    /// terms: it is the one sentence on the screen and reads as prose.
    private var sentence: some View {
        TimelineView(.periodic(from: .now, by: 60)) { context in
            if let line = HomeStateLine.line(history: journey.history, now: context.date) {
                Text(line)
                    .displaySerif(size: 31)
                    .foregroundStyle(Theme.Ink.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: Self.sentenceWidth)
                    .accessibilityIdentifier("home-state-line")
            }
        }
    }

    /// The correction to the button: what it will start, stated, and the way
    /// to change it — quiet and 44 points to the button's 60, so the sizes say
    /// which is the action. `mechanics(for:)` rather than the name and a
    /// length by hand: the length is the one the lead actually plays — the two
    /// part company where a cycle cap falls short — and the Plus mark must show.
    private func startWith(_ lead: DialStop) -> some View {
        Button {
            isChoosing = true
        } label: {
            HStack(spacing: Theme.Spacing.tight) {
                Text(lead.mechanics(for: plus.tier))
                    .font(.subheadline)
                    .multilineTextAlignment(.center)
                    // Wrapped rather than truncated: at accessibility sizes
                    // "Coherent Breathing · 10 min · Plus" is wider than the
                    // page, and a line that says which exercise the button
                    // starts cannot be the line that gets cut.
                    .fixedSize(horizontal: false, vertical: true)

                // The compact chevron, not the right-pointing one: this line
                // raises a sheet, and it is drawn in the shape of that sheet's
                // own grabber. The line already announces itself as a way in,
                // so the glyph only says the same thing to the eye.
                Image(systemName: "chevron.compact.up")
                    .font(.footnote.weight(.semibold))
                    .accessibilityHidden(true)
            }
            .foregroundStyle(Theme.Ink.tertiary)
            .frame(maxWidth: .infinity)
            .tapTarget()
            // On the label rather than on the button, `DoorCard`'s way: an
            // element declared over a `Button` replaces it rather than
            // describing it, and the row stops answering as a button at all.
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Start with \(lead.technique.name), \(lead.duration.spelled)")
        }
        .buttonStyle(.plain)
        .accessibilityHint("Chooses the exercise and length")
        .accessibilityIdentifier("home-start-with")
    }

    /// Whether anybody can see the orb breathe.
    private var isBreathing: Bool {
        scenePhase == .active && isOnScreen && !isShowingSettings && launcher.started == nil
    }

    private func leaveIfAsked() {
        guard isLeavingForExercises else { return }
        isLeavingForExercises = false
        openExercises()
    }
}
