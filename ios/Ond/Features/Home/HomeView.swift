import OndKit
import OndStyle
import OndUI
import SwiftUI

/// Home: the breath at rest, one true sentence, and one button.
///
/// Three things, and everything else that once stood here is somewhere
/// better — the practice list on Exercises, the heart around your practice
/// on Progress. The orb breathes at Coherent pace whatever the button will
/// start, because an orb following a three-a-minute exercise would read as a
/// stall; the sentence says where the week stands or says nothing; the button
/// starts the default, and the one line under it is where the default stops
/// being true.
///
/// It stands under its own masthead rather than a navigation title: the
/// wordmark row is page content — Home opens with the app's name, not a
/// section heading — so the system bar is hidden here and Settings reaches
/// this screen through the gear beside the wordmark.
///
/// **What to offer is `HomeOffer`'s, not this file's.** The default, the two
/// rows beside it, and the length the button plays are all that type's, so the
/// rules stay under test — the app target has no bundle to put one in. The
/// offer is computed rather than held: three rows over a thirteen-entry
/// catalogue is nothing, and every input it reads is observed, so a star made
/// two tabs away or a dial moved on the Exercises tab re-draws the line here
/// without a trigger per input.
struct HomeView: View {
    let catalogue: TechniqueListModel
    let occasions: OccasionCatalogueModel
    let sessions: any SessionRecording

    /// The exercises this person composed, so a choice or a star on one
    /// resolves to a row. Beside the catalogue rather than folded into it, for
    /// the reason `AppRoots` keeps them apart: two services, two loads, and
    /// only one of them needs an identity.
    let own: UserTechniqueModel

    /// The history behind the sentence, and behind which exercise a goal
    /// recommends.
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

    /// Whether the sheet's "All exercises" row was taken. The tab switch waits
    /// for the dismissal rather than racing it: moving the selection under a
    /// live presentation is the one order SwiftUI does not promise to honour.
    @State private var isLeavingForExercises = false

    /// The orb's side. The spec's resting orb, with the outer ring standing
    /// well clear of the core — the card's inner ring sat too close at this
    /// size to read as a breath's reach.
    private static let orbSide: CGFloat = 200

    /// The gap between the button and its line: the spec's own number, so the
    /// two read as one control rather than as a button and a caption. Off the
    /// four-point rhythm on `Theme.Spacing.page`'s terms.
    private static let lineGap: CGFloat = 6

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
        // The local read first, so the sentence is complete before anything
        // touches the network; the fetches then run behind what is already
        // drawn. The occasions are loaded here even though Home no longer
        // offers a protocol, because this is the tab every launch lands on and
        // Protocols should arrive warm.
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
    }

    /// Home arrives whole or not at all: the button resolves a slug against
    /// the catalogue, so there is nothing to draw until that has landed — and
    /// something to say when it never does.
    @ViewBuilder
    private var content: some View {
        switch catalogue.state {
        case .loading:
            ProgressView()

        case let .loaded(techniques) where techniques.isEmpty:
            EmptyCatalogueView(retry: retryReferenceData)

        case let .loaded(techniques):
            if let offer = offer(over: techniques) {
                screen(offer)
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

    private func offer(over techniques: [Technique]) -> HomeOffer? {
        HomeOffer(
            techniques: techniques,
            authored: own.techniques,
            starred: stars.starred,
            goals: profiles.profile.goals,
            history: journey.history,
            choice: choice.choice,
            dialled: settings.overrides(forSlugsOf: techniques + own.techniques)
        )
    }

    private func screen(_ offer: HomeOffer) -> some View {
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
            .buttonStyle(.inkAction(minHeight: 60))
            .accessibilityLabel("Breathe, \(offer.lead.spokenLabel(for: plus.tier))")
            .accessibilityHint("Starts the session")
            .accessibilityIdentifier("home-breathe")

            startWith(offer.lead)
                .padding(.top, Self.lineGap)
        }
        .padding(.horizontal, Theme.Spacing.page)
        .padding(.vertical, Theme.Spacing.standard)
        .sheet(isPresented: $isChoosing, onDismiss: leaveIfAsked) {
            HomeChoiceSheet(offer: offer) {
                isLeavingForExercises = true
                isChoosing = false
            }
        }
    }

    /// The wordmark and the one way to everything that is not practice.
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

            Button {
                isShowingSettings = true
            } label: {
                Image(systemName: "gearshape")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(Theme.Ink.primary)
                    .frame(width: 36, height: 36)
                    .glassEffect(.regular.interactive(), in: .circle)
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
    /// module's one resting clock, paused wherever motion is unwanted, with
    /// Reduce Motion holding the reference instant so the still frame is a
    /// breath mid-way rather than an emptied one. Not a button — the capsule
    /// below is — and hidden from the assistive layer, which has the button's
    /// label to read instead.
    private var orb: some View {
        TimelineView(.animation(
            minimumInterval: Theme.Motion.restfulFrameInterval,
            paused: reduceMotion || scenePhase != .active
        )) { context in
            BreathGlyph(
                side: Self.orbSide,
                pose: .resting(at: reduceMotion ? 0 : context.date.timeIntervalSinceReferenceDate),
                layers: [.halo, .outerRing, .core]
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
                    .displaySerif(size: 28)
                    .foregroundStyle(Theme.Ink.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
                    .accessibilityIdentifier("home-state-line")
            }
        }
    }

    /// The correction to the button: what it will start, stated, and the way
    /// to change it. Quiet and 44 points to the button's 60 — the sizes say
    /// which is the action without a second colour. The length is the one the
    /// lead actually plays, never the one asked for; the two part company
    /// where a cycle cap falls short of the minutes.
    private func startWith(_ lead: DialStop) -> some View {
        Button {
            isChoosing = true
        } label: {
            HStack(spacing: Theme.Spacing.tight) {
                Text("\(lead.technique.name) · \(lead.duration.glanceable)")
                    .font(.subheadline)

                Image(systemName: "chevron.right")
                    .font(.caption2.weight(.semibold))
            }
            .foregroundStyle(Theme.Ink.secondary)
            .frame(maxWidth: .infinity)
            .tapTarget()
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Start with \(lead.technique.name), \(lead.duration.spelled)")
        .accessibilityHint("Chooses the exercise and length")
        .accessibilityIdentifier("home-start-with")
    }

    private func leaveIfAsked() {
        guard isLeavingForExercises else { return }
        isLeavingForExercises = false
        openExercises()
    }
}
