import OndKit
import OndStyle
import OndUI
import SwiftUI

/// What you did, said once and warmly: celebrate what happened, never grade
/// it — a session ended early is still a session. Progression is met here
/// rather than on the Progress tab: a rung is worth saying on the session
/// that earned it, and here it reaches somebody who never opens Progress.
/// Nothing is said on the sessions between, so the ladder cannot nag.
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
                // Naming the exercise is for a session that ran to its end; a
                // rung below is said either way — it was earned either way.
                // Primary ink: secondary measures 3.26:1 against the wash and
                // this line is `.body`, so it gets no large-text allowance.
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
            // Unraised for exactly that: the fill every other card sits on
            // would occlude the wash this one is here to keep.
            .glassCard(raised: false)

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

    /// The "after" half of the mood check, inline: the summary is already the
    /// place somebody sits for a moment, and a fourth full screen before Done
    /// would ask more than the answer is worth. Shown even when the "before"
    /// was skipped — a single reading is still the person's own record.
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
