import OndKit
import OndStyle
import OndUI
import SwiftUI

/// The optional branch somebody can take from the pre-session countdown.
///
/// It exists so the "after" on the summary has something to be an after *of*.
/// Paired with the resting rate the check-ins track, it is the whole of what
/// this app claims to measure — two numbers the person supplied about
/// themselves, and no score önd invented to sit between them.
///
/// One tap either way. Answering restarts the full countdown, and so does Not
/// now, so nobody is charged an extra tap for having an opinion or for changing
/// their mind. The countdown observes `isAsked` and stays paused until a Health
/// write has returned.
///
/// The write goes through this screen's own recorder rather than a closure
/// passed in, for `PulseBadge`'s reason: nothing between here and the
/// composition root has any use for one. Why it is awaited before the check
/// counts as asked is on `MoodCheckModel.answerBefore(_:writing:)`.
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

                MoodScale(selection: check.before) { mood in
                    Task { await check.answerBefore(mood) { await recorder.note($0) } }
                }
                .disabled(check.before != nil)

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
