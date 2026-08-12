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

    /// How this person said they felt on the way in, or nil where they were
    /// never asked or skipped the asking. Only read back beside the answer this
    /// screen collects: on its own it is last week's news.
    let moodBefore: Mood?

    let onDone: () -> Void

    @Environment(SessionSettings.self) private var settings
    @Environment(MoodRecorder.self) private var moodRecorder

    /// The answer this screen collects, held so the row can say it back. Nil
    /// until the tap, and the row is answered once.
    @State private var moodAfter: Mood?

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

            // Above the mood row, so the two answers to "did that do anything"
            // sit together: what the sensor saw, then what the person says.
            PulseCurve()

            moodNote

            Spacer()

            Button("Done", action: onDone)
                .buttonStyle(.capsuleAction(Theme.Accent.brand))
        }
        .padding(Theme.Spacing.loose)
        .foregroundStyle(Theme.Ink.primary)
    }

    /// The "after" half of the mood check, inline rather than on a screen of
    /// its own: the summary is already the place somebody sits for a moment,
    /// and a fourth full screen between the last breath and Done would be the
    /// app asking for more than the answer is worth.
    ///
    /// Shown even when the "before" was skipped. A single reading is still the
    /// person's own record of how a practice left them, and it is Health's to
    /// chart against the nights either side of it.
    @ViewBuilder private var moodNote: some View {
        if settings.asksHowYouFeel {
            VStack(spacing: Theme.Spacing.close) {
                if let moodAfter {
                    Text(answered(moodAfter))
                        .font(.callout)
                        .multilineTextAlignment(.center)
                        .transition(.opacity)
                } else {
                    Text("How do you feel now?")
                        .font(.callout)
                    MoodScale { mood in
                        // The scale is on its way out under a crossfade and
                        // stays tappable for the length of it, so without this
                        // a corrective second tap writes a contradicting sample
                        // beside the first — and nothing downstream could tell
                        // which one was meant.
                        guard moodAfter == nil else { return }
                        moodAfter = mood
                        // Unawaited, unlike the answer before the session: there
                        // is nothing here for a system sheet to interrupt, and
                        // the row has already said the tap landed.
                        Task { await moodRecorder.note(mood) }
                    }
                }
            }
            .animation(.easeIn(duration: 0.3), value: moodAfter)
        }
    }

    /// What the row says once it has its answer: the pair when there is one,
    /// and the reading alone when the way in was skipped.
    ///
    /// Stated, never interpreted. No arrow, no "better", no count of the steps
    /// between them — a person can read two words, and grading the distance
    /// would be the invented score this whole surface exists instead of.
    private func answered(_ after: Mood) -> String {
        guard let moodBefore else { return after.title }
        return "\(moodBefore.title) before · \(after.title) now"
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
