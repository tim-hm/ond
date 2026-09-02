import OndKit
import OndStyle
import OndUI
import SwiftUI

/// The discreet moments, the ones this wrist can keep. The phone answers them
/// with a handoff; this list starts the same thing by hand. Full-screen ones
/// stay off it: a wrist offering one promises a figure and a voice it does not
/// have. The shared `MomentsBoard` join drops moments naming exercises this
/// build no longer holds. Screen says Moments; the wire says occasion.
struct MomentsView: View {
    let occasions: OccasionCatalogueModel
    let catalogue: TechniqueListModel
    let sessions: any SessionRecording
    let journey: JourneyModel

    /// The moment that was tapped. Held rather than passed to a link so
    /// nothing downstream is composed until somebody has actually chosen —
    /// `TechniqueCarouselView.chosen` has the reasoning.
    @State private var chosen: DialStop?

    @Environment(WatchSettings.self) private var settings

    var body: some View {
        content
            .navigationTitle("Moments")
            // A cover rather than a push, as the guided player has: the
            // session ends when its screen goes, and the dismiss guard the
            // screen states cannot stop a back swipe out of a stack.
            .fullScreenCover(item: $chosen) { stop in
                DiscreetSessionView(
                    model: DiscreetSessionModel(
                        technique: stop.technique,
                        occasionSlug: stop.occasionSlug,
                        cues: WatchHapticController(settings: settings),
                        recorder: sessions
                    ),
                    occasionName: stop.title
                ) { _ in
                    // Hung on the session finishing rather than on the cover
                    // closing, on the carousel's reasoning: the RPC must not
                    // start in the same instant the workout session does. The
                    // record is the phone's business — a session started here
                    // was never ordered, so nobody waits to be told of it.
                    Task { await journey.sync() }
                }
            }
            .task {
                async let occasions: Void = occasions.loadIfNeeded()
                async let catalogue: Void = catalogue.loadIfNeeded()
                _ = await (occasions, catalogue)
            }
    }

    @ViewBuilder
    private var content: some View {
        let discreet = discreet

        if !discreet.isEmpty {
            List(discreet) { stop in
                row(stop)
            }
        } else if catalogue.hasSettled, occasions.hasSettled {
            // A build whose export could not be read settles here, and so
            // does one whose seeded moments are all full-screen. Said plainly:
            // a spinner that never stops reads as a hang, and nothing sits
            // behind it to wait for until the next launch's fetch.
            ContentUnavailableView {
                Label("No moments yet", systemImage: "checklist")
            } description: {
                Text("They download with the catalogue, the first time this watch can reach it.")
            }
        } else {
            ProgressView()
        }
    }

    private func row(_ stop: DialStop) -> some View {
        Button {
            chosen = stop
        } label: {
            VStack(alignment: .leading, spacing: Theme.Spacing.tight) {
                Text(stop.title)
                    .font(.caption)
                    .foregroundStyle(Theme.Ink.primary)

                // The cadence's span, not the technique's: a discreet session
                // is mostly silence, and its half hour is the number that
                // changes the decision to start one.
                Text(
                    DiscreetCadence.duration(of: stop.technique)
                        .formatted(.time(pattern: .minuteSecond))
                )
                .font(.caption2)
                .monospacedDigit()
                .foregroundStyle(Theme.Ink.tertiary)
            }
        }
        .accessibilityHint("Taps the rhythm quietly, with nothing on screen and no sound.")
    }

    /// The discreet moments the catalogue can resolve.
    ///
    /// Rebuilt per pass rather than held, unlike the phone's: the wrist has no
    /// dials to fold in and no pills to re-filter, so this is a `compactMap` over
    /// a few dozen occasions and nothing more.
    private var discreet: [DialStop] {
        guard case let .loaded(techniques) = catalogue.state else { return [] }

        return MomentsBoard(techniques: techniques, occasions: occasions.available)
            .delivered(on: .discreet)
    }
}
