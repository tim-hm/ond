import OndKit
import OndUI
import SwiftUI

/// The coach's exercise offer as a card under its reply. Receives the
/// technique already dialled by the offer, so what the summary line describes
/// is exactly the session Start begins — a card summarising the catalogue
/// defaults over a dialled launch would promise one session and start another.
struct ExerciseOfferCard: View {
    let technique: Technique
    let start: () -> Void

    var body: some View {
        OfferCard(
            eyebrow: "Try this",
            title: technique.name,
            summary: technique.offerSummary,
            goal: technique.goal
        ) {
            Button("Begin", action: start)
                .buttonStyle(.borderedProminent)
                .tint(Theme.Ink.primary)
                .foregroundStyle(Theme.Surface.ground)
        }
    }
}
