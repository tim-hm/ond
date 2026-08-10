import OndKit
import OndStyle
import OndUI
import SwiftUI

/// What you did, said once and warmly.
///
/// The copy rule from the business plan holds here more than anywhere: celebrate
/// what happened, never grade it. A session ended early is still a session — the
/// screen says so and then gets out of the way.
///
/// It is also where progression is met, rather than the Journey tab: a rung is
/// worth saying something about on the session that earned it, and saying it
/// here means it reaches somebody who never opens Journey at all. Nothing is
/// said on the sessions in between, so the ladder cannot become a thing that
/// nags.
struct SessionSummaryView: View {
    let record: SessionRecord
    let technique: Technique

    /// The stage this session earned, if it earned one. Arrives a moment after
    /// the screen does — see `SessionModel.reachedStage`.
    let reached: PracticeStage?

    let onDone: () -> Void

    var body: some View {
        VStack(spacing: Theme.Spacing.loose) {
            Spacer()

            VStack(spacing: Theme.Spacing.close) {
                Text(record.headline)
                    .font(.largeTitle.weight(.medium))
                // Naming the exercise is for a session that ran to its end; one
                // stopped by hand has heard everything it needs to in the
                // headline. A rung, below, is said either way — it was earned
                // either way.
                //
                // Primary ink, like everything else on `accentGround(_:)`: the
                // secondary step measures 3.26:1 against the wash and this line
                // is `.body`, so it gets no large-text allowance.
                if record.completed {
                    Text("That's \(technique.name) done.")
                        .font(.body)
                        .multilineTextAlignment(.center)
                }

                if let reached {
                    Text(reached.arrival)
                        .font(.callout.weight(.medium))
                        .multilineTextAlignment(.center)
                        .transition(.opacity)
                }
            }
            .animation(.easeIn(duration: 0.4), value: reached)

            HStack(spacing: Theme.Spacing.loose) {
                stat(record.cyclesLabel, "\(record.cyclesCompleted)")
                stat("minutes", record.duration.formatted(.time(pattern: .minuteSecond)))
                stat(record.breathsLabel, "\(record.breathCount)")
            }
            .frame(maxWidth: .infinity)
            .padding(Theme.Spacing.standard)
            // Translucent, so the accent wash the session was drawn in still
            // shows through the one thing left on the screen.
            .background(Theme.Surface.raised.opacity(0.6), in: card)
            .overlay(card.stroke(Theme.Surface.line))

            Spacer()

            Button("Done", action: onDone)
                .buttonStyle(.capsuleAction(technique.goal.accent))
        }
        .padding(Theme.Spacing.loose)
        .foregroundStyle(Theme.Ink.primary)
    }

    private var card: RoundedRectangle {
        RoundedRectangle(cornerRadius: Theme.Radius.card)
    }

    private func stat(_ label: String, _ value: String) -> some View {
        VStack(spacing: Theme.Spacing.tight) {
            Text(value)
                .font(.title.weight(.medium))
                .monospacedDigit()
            // Primary, like everything else on `accentGround(_:)`. A card this
            // translucent is governed by the wash behind it rather than by
            // `Surface.raised`, so it inherits that ground's rule: secondary
            // resolves to 4.35:1 against the composite in the light appearance,
            // under AA for `.caption` copy, which gets no large-text allowance
            // at any weight. Thickening the card to 0.68 would carry secondary
            // instead, and was not worth the wash it would hide. Hierarchy here
            // is the step from `.title` to `.caption`, which is all the rest of
            // the screen has to spend too.
            Text(label)
                .font(.caption)
        }
        .accessibilityElement(children: .combine)
    }
}
