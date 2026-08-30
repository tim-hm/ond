import OndKit
import OndStyle
import OndUI
import SwiftUI

/// The optional branch from the pre-session countdown; it exists so the
/// summary's "after" has something to be an after of. Answering and Not now
/// both restart the full countdown, which observes `isAsked` and stays paused
/// until the Health write returns — why is on `MoodCheckModel.answerBefore`.
/// The recorder comes from the environment, for `PulseBadge`'s reason.
struct MoodCheckView: View {
    let check: MoodCheckModel

    @Environment(MoodRecorder.self) private var recorder

    var body: some View {
        VStack(spacing: Theme.Spacing.loose) {
            Spacer()

            VStack(spacing: Theme.Spacing.loose) {
                Text("How do you feel right now?")
                    .font(.largeTitle.weight(.medium))
                    .multilineTextAlignment(.center)

                VStack(spacing: Theme.Spacing.close) {
                    MoodScale(selection: check.before) { mood in
                        Task { await check.answerBefore(mood) { await recorder.note($0) } }
                    }
                    .disabled(check.before != nil)

                    // Said before the answer rather than after: what the check
                    // is for is cheaper to state than to correct.
                    Text(MoodCheckModel.caption)
                        .font(.footnote)
                }

                Button("Not now", action: check.skipBefore)
                    .font(.subheadline)
                    .tapTarget()
                    .disabled(check.before != nil)
            }

            Spacer()
        }
        .padding(Theme.Spacing.loose)
        // Primary is the only ink that clears AA over the accent wash, as on
        // every other screen a session draws at rest.
        .foregroundStyle(Theme.Ink.primary)
    }
}
