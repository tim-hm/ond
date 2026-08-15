import OndKit
import OndStyle
import OndUI
import SwiftUI

/// The protocols whose promise only this wrist can keep: the discreet ones.
///
/// The other end of the phone's refusal. Its Protocols tab shows every one and
/// answers a discreet one with a handoff — this list is where somebody starts
/// the same thing by hand. Full-screen protocols stay off it for the mirrored
/// reason: they are phone screens, and a wrist offering one would be promising a
/// figure and a voice it does not have.
///
/// The join is `ProtocolsBoard`'s, shared with the phone. This screen kept its
/// own copy of it — a `bySlug` dictionary and the same compactMap — which is two
/// statements of one rule on two devices, and the rule has teeth: a protocol
/// naming an exercise this build no longer holds has to be dropped rather than
/// drawn as a row that opens onto nothing.
///
/// Named Protocols to the person and `Occasion` in the domain, exactly as on the
/// phone: the wire, the records and the seed all still say occasion, and only
/// the words on screen were changed.
struct ProtocolsView: View {
    let occasions: OccasionCatalogueModel
    let catalogue: TechniqueListModel
    let sessions: any SessionRecording
    let journey: JourneyModel

    /// The protocol that was tapped. Held rather than passed to a link so
    /// nothing downstream is composed until somebody has actually chosen —
    /// `TechniqueCarouselView.chosen` has the reasoning.
    @State private var chosen: DialStop?

    @Environment(WatchSettings.self) private var settings

    var body: some View {
        content
            .navigationTitle("Protocols")
            // The drain is hung off the session finishing rather than the
            // screen going away, on the carousel's exact reasoning: a push
            // counts as going away, and the RPC must not start in the same
            // instant the workout session does.
            .navigationDestination(item: $chosen) { stop in
                DiscreetSessionView(
                    model: DiscreetSessionModel(
                        technique: stop.technique,
                        occasionSlug: stop.occasionSlug,
                        cues: WatchHapticController(settings: settings),
                        recorder: sessions
                    ),
                    occasionName: stop.title
                ) { _ in
                    // The record itself is the phone's business, not this
                    // screen's: a session started here was never ordered, so
                    // there is nobody waiting to be told which one it was.
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
            // Reachable by design: the bundled seed carries no occasions, so a
            // first launch that cannot reach the server settles here. Said
            // plainly rather than spun forever — a spinner that never stops
            // reads as a hang, and there is nothing behind it to wait for
            // until the next launch's fetch.
            ContentUnavailableView {
                Label("No protocols yet", systemImage: "checklist")
            } description: {
                Text("They arrive with the catalogue, the first time this watch can reach it.")
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
        .accessibilityHint("Taps the rhythm out quietly. Nothing on screen, nothing to hear.")
    }

    /// The discreet protocols the catalogue can resolve.
    ///
    /// Rebuilt per pass rather than held, unlike the phone's: the wrist has no
    /// dials to fold in and no pills to re-filter, so this is a `compactMap` over
    /// a few dozen occasions and nothing more.
    private var discreet: [DialStop] {
        guard case let .loaded(techniques) = catalogue.state else { return [] }

        return ProtocolsBoard(techniques: techniques, occasions: occasions.available)
            .delivered(on: .discreet)
    }
}
