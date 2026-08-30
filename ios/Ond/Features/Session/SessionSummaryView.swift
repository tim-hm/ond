import OndKit
import OndStyle
import OndUI
import SwiftUI

/// The session with the breathing removed: the same ground, the same three
/// slots the phase words stood in, and the figures where the orb was. It says
/// the session happened, says what it was, and offers one way out. The cases,
/// the strings and the reserved heights are in docs/product/session-summary.md.
struct SessionSummaryView: View {
    let record: SessionRecord

    /// The exercise's own name, never the occasion's. The note holds one line,
    /// and an occasion title is a sentence — it would be cut short there and
    /// would read as the wrong noun in the sentence around it.
    let exercise: String

    /// The stage this session earned, if it earned one. Arrives a moment after
    /// the screen does — see `SessionModel.reachedStage` — which is why the
    /// mark slot below holds its height whether or not it has a sentence.
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

            slots
            figures

            // Above the mood row, so the two answers to "did that do anything"
            // sit together: what the sensor saw, then what the person says.
            PulseCurve()

            moodNote

            Spacer()

            Button("Done", action: onDone)
                .buttonStyle(.inkAction)
        }
        .padding(.horizontal, Theme.Spacing.page)
        .padding(.vertical, Theme.Spacing.loose)
        .foregroundStyle(Theme.Ink.primary)
        // Stilled: the breathing has stopped, so the field holds where the
        // session left it rather than repainting the screen while it is read.
        .sessionGround(stilled: true)
    }

    /// What happened, what it was, and the rung it crossed, in the heights
    /// `SessionSlots` reserves. Capped with the session's words, and for their
    /// reason: an accessibility size would spill the words out of them.
    private var slots: some View {
        VStack(spacing: 0) {
            Text(SessionSummaryLines.headline(for: record))
                .displaySerif(size: SessionSlots.actionSize)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .frame(height: SessionSlots.actionHeight)

            Text(SessionSummaryLines.note(for: record, exercise: exercise))
                .font(.body)
                .foregroundStyle(Theme.Ink.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .frame(height: SessionSlots.qualifierHeight)

            mark
                .frame(height: SessionSlots.countHeight)
                .animation(.easeIn(duration: 0.4), value: reached)
        }
        .multilineTextAlignment(.center)
        .dynamicTypeSize(...SessionWords.mostGrowth)
    }

    @ViewBuilder private var mark: some View {
        if let reached {
            Text(reached.arrival)
                .font(.subheadline)
                .foregroundStyle(Theme.Ink.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .transition(.opacity)
        }
    }

    /// The evidence, in Progress's own treatment. A figure with a zero in it
    /// is absent rather than empty — the rule is `SessionSummaryLines.figures`.
    private var figures: some View {
        HStack(alignment: .top, spacing: Theme.Spacing.standard) {
            ForEach(SessionSummaryLines.figures(for: record)) { figure in
                VStack(spacing: Theme.Spacing.tight) {
                    Text(figure.value)
                        .font(.title2.weight(.semibold).monospacedDigit())

                    Text(figure.label)
                        .font(.caption)
                        .foregroundStyle(Theme.Ink.secondary)
                }
                .frame(maxWidth: .infinity)
                .accessibilityElement(children: .combine)
            }
        }
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
                        .font(.body)
                        .transition(.opacity)
                } else {
                    Text("How do you feel now?")
                        .font(.body)

                    MoodScale { tapped in
                        Task { await mood.answerAfter(tapped) { await moodRecorder.note($0) } }
                    }
                }

                Text(MoodCheckModel.caption)
                    .font(.footnote)
                    .foregroundStyle(Theme.Ink.secondary)
            }
            .multilineTextAlignment(.center)
            .animation(.easeIn(duration: 0.3), value: mood.after)
        }
    }
}
