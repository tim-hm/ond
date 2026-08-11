import OndKit
import OndStyle
import OndUI
import SwiftUI

/// The occasions whose promise only this wrist can keep: the discreet ones.
///
/// The other end of the phone's refusal. Its home board shows every occasion
/// and answers a discreet one with "start it from OndWatch" — this list is
/// where that sentence stops being a dead end. Full-screen occasions stay off
/// it for the mirrored reason: they are phone screens, and a wrist offering
/// one would be promising a figure and a voice it does not have.
struct MomentsView: View {
    /// One row: an occasion joined to the technique it prescribes.
    ///
    /// Joined once, here, so the list, each row's duration, and the pushed
    /// session all read the same resolution — an occasion naming a technique
    /// this build does not hold is dropped at the join, the same rule the
    /// phone's dial applies.
    private struct Moment: Identifiable, Hashable {
        let occasion: Occasion
        let technique: Technique

        var id: String {
            occasion.id
        }
    }

    let routes: RoutesModel
    let catalogue: TechniqueListModel
    let sessions: any SessionRecording
    let journey: JourneyModel

    /// The moment that was tapped. Held rather than passed to a link so
    /// nothing downstream is composed until somebody has actually chosen —
    /// `TechniqueCarouselView.chosen` has the reasoning.
    @State private var chosen: Moment?

    @Environment(WatchSettings.self) private var settings

    var body: some View {
        content
            .navigationTitle("Moments")
            // The drain is hung off the session finishing rather than the
            // screen going away, on the carousel's exact reasoning: a push
            // counts as going away, and the RPC must not start in the same
            // instant the workout session does.
            .navigationDestination(item: $chosen) { moment in
                DiscreetSessionView(
                    model: DiscreetSessionModel(
                        technique: moment.technique,
                        occasionSlug: moment.occasion.slug,
                        cues: WatchHapticController(settings: settings),
                        recorder: sessions
                    ),
                    occasionName: moment.occasion.name
                ) {
                    Task { await journey.sync() }
                }
            }
            .task {
                async let routes: Void = routes.loadIfNeeded()
                async let catalogue: Void = catalogue.loadIfNeeded()
                _ = await (routes, catalogue)
            }
    }

    @ViewBuilder
    private var content: some View {
        let moments = moments

        if !moments.isEmpty {
            List(moments) { moment in
                row(moment)
            }
        } else if hasSettled {
            // Reachable by design: the bundled seed carries no routes, so a
            // first launch that cannot reach the server settles here. Said
            // plainly rather than spun forever — a spinner that never stops
            // reads as a hang, and there is nothing behind it to wait for
            // until the next launch's fetch.
            ContentUnavailableView {
                Label("No moments yet", systemImage: "sparkles")
            } description: {
                Text("They arrive with the catalogue, the first time this watch can reach it.")
            }
        } else {
            ProgressView()
        }
    }

    /// Whether both loads have answered, either way. A failure settles too:
    /// routes are a layer over the catalogue, and an error banner would report
    /// a degradation nobody on a wrist can act on.
    private var hasSettled: Bool {
        if case .loading = routes.state {
            return false
        }
        if case .loading = catalogue.state {
            return false
        }
        return true
    }

    private func row(_ moment: Moment) -> some View {
        Button {
            chosen = moment
        } label: {
            VStack(alignment: .leading, spacing: Theme.Spacing.tight) {
                Text(moment.occasion.name)
                    .font(.caption)
                    .foregroundStyle(Theme.Ink.primary)

                // The cadence's span, not the technique's: a discreet session
                // is mostly silence, and its half hour is the number that
                // changes the decision to start one.
                Text(
                    DiscreetCadence.duration(of: moment.technique)
                        .formatted(.time(pattern: .minuteSecond))
                )
                .font(.caption2)
                .monospacedDigit()
                .foregroundStyle(Theme.Ink.tertiary)
            }
        }
        .accessibilityHint("Taps the rhythm out quietly. Nothing on screen, nothing to hear.")
    }

    /// The discreet occasions the catalogue can resolve, joined to their
    /// techniques.
    private var moments: [Moment] {
        guard case let .loaded(techniques) = catalogue.state else { return [] }
        // First wins on a duplicate slug: the seed forbids one, but a server
        // that shipped one anyway is not worth trapping a wrist over.
        let bySlug = Dictionary(
            techniques.map { ($0.slug, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        return routes.available.occasions.compactMap { occasion in
            guard occasion.prescription.surface == .discreet,
                  let technique = bySlug[occasion.prescription.techniqueSlug]
            else { return nil }
            return Moment(occasion: occasion, technique: technique)
        }
    }
}
