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
                Text(technique.offerSummary)
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
}
