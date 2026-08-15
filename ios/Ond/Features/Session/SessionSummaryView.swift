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
/// It is also where progression is met, rather than the Progress tab: a rung is
/// worth saying something about on the session that earned it, and saying it
/// here means it reaches somebody who never opens Progress at all. Nothing is
/// said on the sessions in between, so the ladder cannot become a thing that
/// nags.
struct SessionSummaryView: View {
    let record: SessionRecord
    let title: String

    /// The stage this session earned, if it earned one. Arrives a moment after
    /// the screen does — see `SessionModel.reachedStage`.
    let reached: PracticeStage?

    /// Both halves of "how do you feel" — the answer given before the
    /// breathing, and the one this screen collects. Shared with the screen that
    /// asked the first, which is what lets the row say the pair back.
    let mood: MoodCheckModel

    let onDone: () -> Void

    @Environment(SessionSettings.self) private var settings
    @Environment(MoodRecorder.self) private var moodRecorder

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
                    Text("That's \(title) done.")
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
            // Glass, so the accent wash the session was drawn in still shows
            // through the one thing left on the screen — and the material,
            // not a hand-tuned opacity, decides what stays legible on it.
            .glassCard()

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
                if let note = mood.note {
                    Text(note)
                        .font(.callout)
                        .multilineTextAlignment(.center)
                        .transition(.opacity)
                } else {
                    Text("How do you feel now?")
                        .font(.callout)
                    MoodScale { tapped in
                        Task { await mood.answerAfter(tapped) { await moodRecorder.note($0) } }
                    }
                }
            }
            .animation(.easeIn(duration: 0.3), value: mood.after)
        }
    }

    private func stat(_ label: String, _ value: String) -> some View {
        VStack(spacing: Theme.Spacing.tight) {
            Text(value)
                .font(.title.weight(.medium))
                .monospacedDigit()
            // Primary, like everything else on `accentGround(_:)`: hierarchy
            // here is the step from `.title` to `.caption`, not a tone the
            // wash would spend.
            Text(label)
                .font(.caption)
        }
        .accessibilityElement(children: .combine)
    }
}
