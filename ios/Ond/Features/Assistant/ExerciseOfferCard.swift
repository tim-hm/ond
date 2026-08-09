import OndKit
import OndUI
import SwiftUI

/// The coach's exercise offer as a card under its reply: which exercise,
/// how it is dialled, and the one action that starts it.
///
/// Receives the technique already dialled by the offer, so what the summary
/// line describes is exactly the session Start begins — a card summarising the
/// catalogue defaults over a dialled launch would promise one session and
/// start another.
struct ExerciseOfferCard: View {
    let technique: Technique
    let start: () -> Void

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: Theme.Spacing.standard) {
            VStack(alignment: .leading, spacing: Theme.Spacing.tight) {
                Text(technique.name)
                    .font(.headline)
                    .foregroundStyle(Theme.Ink.primary)
                Text(summary)
                    .font(.footnote)
                    .foregroundStyle(Theme.Ink.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Button("Start", action: start)
                .buttonStyle(.borderedProminent)
                .tint(Theme.Accent.brand)
        }
        .padding(Theme.Spacing.standard)
        .glassCard()
    }

    /// One line of what the dialled session is: rounds, then either the single
    /// stage's cycles and breath rhythm or, for a staged protocol, the stage
    /// count — the same altitude the exercise list summarises at.
    private var summary: String {
        let rounds = technique.recommendedRounds
        let roundsPart = "\(rounds) \(rounds == 1 ? "round" : "rounds")"

        guard technique.stages.count == 1, let stage = technique.stages.first else {
            return "\(roundsPart) · \(technique.stages.count) stages"
        }

        let rhythm = stage.phases
            .map(\.duration.inSeconds)
            .joined(separator: "-")
        let cyclesPart = stage.openEnded ? "open-ended" : "\(stage.cycles) cycles"
        return "\(roundsPart) · \(cyclesPart) · \(rhythm)"
    }
}
