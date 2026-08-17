import OndKit
import OndUI
import SwiftUI

/// The watch app's front door: what to breathe, then where else to go.
///
/// It was three navigation rows and nothing else, which made every launch land
/// on a decision about *where* rather than on something to do. The wrist is the
/// device somebody reaches for without looking, so the three cards at the top
/// are the whole of the standalone promise — last night's exercise, under the
/// thumb, before the phone has ever been in range. `WristShelf` owns which
/// three and in what order, because every one of those rules is a claim about
/// somebody's history.
///
/// The doors stay below them. Protocols before Exercises, which is the phone's
/// order in `AppChrome` (`Home · Protocols · Exercises · Progress · Coach`) with
/// the destinations this wrist does not carry left out. Two devices disagreeing
/// about which of two rows comes first is the kind of thing somebody notices
/// without being able to say why. Nothing reconciles the two lists — the symbols
/// are already kept in step by hand, and the order joins them.
struct RootMenuView: View {
    let catalogue: TechniqueListModel
    let occasions: OccasionCatalogueModel
    let sessions: any SessionRecording
    let journey: JourneyModel

    @Environment(WatchSettings.self) private var settings

    /// The exercise that was tapped, and what covers the door. Held rather than
    /// passed to a link so nothing downstream is composed until somebody has
    /// actually chosen — `TechniqueCarouselView`'s reasoning, and its
    /// consequence: End is then the one way out.
    @State private var chosen: Technique?

    /// The three cards, folded when their inputs move rather than read.
    ///
    /// `HomeView`'s shape, for its reason and more sharply: as a computed
    /// property this sorted the whole history and built three techniques on
    /// every body pass — including the two a session cover costs going up and
    /// coming down, on the slowest processor in the product.
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
    }

    /// The catalogue, or nothing until it lands.
    private var loaded: [Technique] {
        guard case let .loaded(techniques) = catalogue.state else { return [] }
        return techniques
    }

    private func fold() {
        shelf = WristShelf(techniques: loaded, history: journey.history).stops
    }

    /// The wordmark, and the time beside it — the one number a watch face is
    /// always asked for, and the reason this screen can stand alone at all.
    private var masthead: some View {
        HStack(alignment: .firstTextBaseline) {
            // Lowercase, and never uppercased: the name is önd, and ÖND is a
            // different word wearing its hat.
            Text("önd")
                .displaySerif(size: 22)
                .foregroundStyle(Theme.Ink.primary)

            Spacer(minLength: Theme.Spacing.tight)

            Text(.now, style: .time)
                .font(.caption2)
                .monospacedDigit()
                .foregroundStyle(Theme.Breath.inhale)
        }
        .listRowInsets(EdgeInsets())
        .listRowBackground(Color.clear)
        .accessibilityAddTraits(.isHeader)
    }

    @ViewBuilder
    private var doors: some View {
        NavigationLink {
            ProtocolsView(
                occasions: occasions,
                catalogue: catalogue,
                sessions: sessions,
                journey: journey
            )
        } label: {
            // The protocols only this wrist can deliver — the door the phone's
            // handoff sheet points at. The phone's own Protocols tab carries the
            // same symbol.
            Label("Protocols", systemImage: "checklist")
        }

        NavigationLink {
            TechniqueCarouselView(model: catalogue, sessions: sessions, journey: journey)
        } label: {
            Label("Exercises", systemImage: "figure.mind.and.body")
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
