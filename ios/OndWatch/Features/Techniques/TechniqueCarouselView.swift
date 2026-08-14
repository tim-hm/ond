import OndKit
import OndStyle
import OndUI
import SwiftUI

/// The catalogue: one technique to a page, turned with the Digital Crown.
///
/// Shaped like a Fitness workout card, and for the same reason — a wrist screen
/// holds one picture, one name, and one button before it stops being glanceable.
/// Everything that used to sit on the card (the intent word, the cadence, the
/// summary) has gone: none of it is read while choosing on a watch, and all of
/// it is a tap away in the hand.
struct TechniqueCarouselView: View {
    let model: TechniqueListModel
    let sessions: any SessionRecording
    let journey: JourneyModel

    /// The technique that was tapped, and what covers the carousel. Held rather
    /// than passed to a link so nothing downstream is composed until somebody
    /// has actually chosen.
    @State private var chosen: Technique?

    @Environment(WatchSettings.self) private var settings

    var body: some View {
        content
            .navigationTitle("Exercises")
            // Outside the vertical pager so its crown indicator cannot remain
            // over the breathing face. The cover also makes End the one exit:
            // there is no navigation back button to abandon a live model.
            .fullScreenCover(item: $chosen) { technique in
                NavigationStack {
                    SessionView(model: session(for: technique)) {
                        Task { await journey.sync() }
                    }
                }
                .interactiveDismissDisabled()
            }
            .task { await model.loadIfNeeded() }
    }

    @ViewBuilder
    private var content: some View {
        switch model.state {
        case .loading:
            ProgressView()

        case let .loaded(techniques):
            TabView {
                ForEach(techniques) { technique in
                    page(technique)
                }
            }
            .tabViewStyle(.verticalPage)

        case let .failed(message):
            // Effectively unreachable: `CachedTechniqueRepository` serves the
            // last catalogue the server sent, and before there is one, the seed
            // this build shipped with. Getting here means the bundled export
            // failed to decode, which `BundledCatalogueTests` is what actually
            // guards against.
            unreachable(message)
        }
    }

    /// One technique: its orb, its name, and the button that starts it.
    private func page(_ technique: Technique) -> some View {
        VStack(spacing: Theme.Spacing.close) {
            TechniqueGlyph(technique: technique)
                .frame(height: 76)
                .padding(.horizontal, Theme.Spacing.close)

            VStack(spacing: 0) {
                Text(technique.name)
                    .font(.caption)
                    .foregroundStyle(Theme.Ink.primary)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)

                // The one number that survived the redesign, because it is the
                // one that changes the answer: two minutes and nine minutes are
                // different decisions, and the rest of what a card used to carry
                // is not read on a wrist.
                Text(technique.plannedDuration.formatted(.time(pattern: .minuteSecond)))
                    .font(.caption2)
                    .monospacedDigit()
                    .foregroundStyle(Theme.Ink.tertiary)
            }
            .accessibilityElement(children: .combine)

            play(technique)
        }
        // Clear of the vertical page indicator, which draws over the right edge.
        .padding(.trailing, Theme.Spacing.close)
    }

    /// Fitness's play button, in the technique's colour: the one control on the
    /// page, and big enough to hit without looking.
    private func play(_ technique: Technique) -> some View {
        Button {
            chosen = technique
        } label: {
            Image(systemName: "play.fill")
                .font(.title3)
                .foregroundStyle(Theme.Surface.ground)
                .frame(width: 42, height: 42)
                .background(technique.goal.accent, in: Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Begin \(technique.name)")
    }

    /// Built at the tap rather than held: a session is a one-shot object, and
    /// one composed when this screen appeared would already have been used by
    /// the time somebody comes back and starts again.
    private func session(for technique: Technique) -> SessionModel {
        SessionModel(
            technique: technique,
            cues: WatchHapticController(settings: settings),
            recorder: sessions
        )
    }

    private func unreachable(_ message: String) -> some View {
        ContentUnavailableView {
            Label("Can't reach the catalogue", systemImage: "wifi.slash")
        } description: {
            Text(message)
        } actions: {
            Button("Try again") {
                Task { await model.load() }
            }
        }
    }
}
