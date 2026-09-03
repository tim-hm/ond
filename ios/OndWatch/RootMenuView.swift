import OndKit
import OndUI
import SwiftUI

/// The watch app's front door: what to breathe, then where else to go. The
/// three cards at the top are the standalone promise — last night's exercise
/// under the thumb before the phone was ever in range — and `WristShelf` owns
/// which three, in what order. The doors keep the phone's `AppChrome` order,
/// minus what this wrist lacks; nothing reconciles that — kept in step by hand.
struct RootMenuView: View {
    let catalogue: TechniqueListModel
    let occasions: OccasionCatalogueModel
    let sessions: any SessionRecording
    let journey: JourneyModel

    @Environment(WatchSettings.self) private var settings

    /// Read for the tier alone: the shelf must not offer an exercise the phone
    /// would put behind the paywall.
    @Environment(WatchHandoffInbox.self) private var phone

    /// The exercise that was tapped, and what covers the door. Held rather than
    /// passed to a link so nothing downstream is composed until somebody has
    /// actually chosen — `TechniqueCarouselView`'s reasoning, and its
    /// consequence: End is then the one way out.
    @State private var chosen: Technique?

    /// The three cards, folded when their inputs move rather than read —
    /// `HomeView`'s shape, more sharply: as a computed property this sorted
    /// the whole history and built three techniques on every body pass, on
    /// the slowest processor in the product.
    @State private var shelf: [DialStop] = []

    var body: some View {
        List {
            masthead

            ForEach(Array(shelf.enumerated()), id: \.element.id) { index, stop in
                WristStopCard(stop: stop, leads: index == 0) {
                    chosen = stop.dialled
                }
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
            }

            doors
        }
        .navigationTitle("önd")
        // Hidden because the masthead below is the app's name in its own face:
        // a navigation title saying it again would be the word twice on a
        // screen with room for neither.
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden)
        .fullScreenCover(item: $chosen) { technique in
            NavigationStack {
                SessionView(model: session(for: technique)) {
                    Task { await journey.sync() }
                }
            }
            .interactiveDismissDisabled()
        }
        .task { await journey.refresh() }
        // One trigger per input, each folding only what that input feeds. The
        // history keys on the records themselves rather than on their count,
        // on `HomeView`'s reasoning: a sync that amends a session without
        // adding one still changes what this door offers.
        .onChange(of: journey.history, initial: true) { _, _ in fold() }
        .onChange(of: loaded.map(\.id)) { _, _ in fold() }
        // A lapsed or renewed subscription changes what this door may offer,
        // and it arrives from the phone rather than from anything tapped here.
        .onChange(of: phone.entitledTier) { _, _ in fold() }
    }

    /// The catalogue, or nothing until it lands.
    private var loaded: [Technique] {
        guard case let .loaded(techniques) = catalogue.state else { return [] }
        return techniques
    }

    private func fold() {
        shelf = WristShelf(
            techniques: loaded,
            history: journey.history,
            tier: phone.entitledTier
        ).stops
    }

    /// The wordmark, and the time beside it — the one number a watch face is
    /// always asked for, and the reason this screen can stand alone at all.
    private var masthead: some View {
        HStack(alignment: .firstTextBaseline) {
            // Lowercase, and never uppercased: the name is önd, and ÖND is a
            // different word wearing its hat.
            Text("önd")
                .displaySerif(size: Theme.Metrics.wristDisplaySize)
                .foregroundStyle(Theme.Ink.primary)

            Spacer(minLength: Theme.Spacing.tight)

            // Untinted, as the refresh spec §7 asks: this stands for the
            // system's own clock.
            Text(.now, style: .time)
                .font(.caption2)
                .monospacedDigit()
                .foregroundStyle(Theme.Ink.primary)
        }
        .listRowInsets(EdgeInsets())
        .listRowBackground(Color.clear)
        .accessibilityAddTraits(.isHeader)
    }

    @ViewBuilder
    private var doors: some View {
        NavigationLink {
            MomentsView(
                occasions: occasions,
                catalogue: catalogue,
                sessions: sessions,
                journey: journey
            )
        } label: {
            // The moments only this wrist can deliver — the door the phone's
            // handoff sheet points at. The phone's tab now draws `sun.haze`;
            // the wrist keeps the tick list until its own refresh.
            Label("Moments", systemImage: "checklist")
        }

        NavigationLink {
            TechniqueCarouselView(model: catalogue, sessions: sessions, journey: journey)
        } label: {
            Label("Exercises", systemImage: "figure.stand")
        }

        NavigationLink {
            SettingsView()
        } label: {
            Label("Settings", systemImage: "gearshape")
        }
    }

    /// Built at the tap rather than held, on `TechniqueCarouselView`'s terms: a
    /// session is a one-shot object, and one composed when this screen appeared
    /// would already have been used by the time somebody comes back.
    private func session(for technique: Technique) -> SessionModel {
        SessionModel(
            technique: technique,
            cues: WatchHapticController(settings: settings),
            recorder: sessions
        )
    }
}
