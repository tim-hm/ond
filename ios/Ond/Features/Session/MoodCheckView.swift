import OndKit
import OndStyle
import OndUI
import SwiftUI

/// The "before" half of the mood check: the last screen a session shows at
/// rest, between whatever gate got here and the countdown.
///
/// It exists so the "after" on the summary has something to be an after *of*.
/// Paired with the resting rate the check-ins track, it is the whole of what
/// this app claims to measure — two numbers the person supplied about
/// themselves, and no score önd invented to sit between them.
///
/// One tap either way. Answering advances, and so does Skip, so nobody is
/// charged an extra tap for having an opinion or for not having one. Neither is
/// wired back to the screen that opened this: both land on the check, whose
/// `isAsked` is the gate `SessionView` reads.
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

            VStack(spacing: Theme.Spacing.close) {
                Text("How do you feel right now?")
                    .font(.largeTitle.weight(.medium))
                    .multilineTextAlignment(.center)
                Text(
                    "Answer again at the end, and the pair says whether this is doing anything. It's kept in Health, on this phone — önd never sees it."
                )
                .font(.body)
                .multilineTextAlignment(.center)
            }

            Spacer()

            MoodScale(selection: check.before) { mood in
                Task { await check.answerBefore(mood) { await recorder.note($0) } }
            }

            Spacer()

            Button("Skip", action: check.skipBefore)
                .font(.subheadline)
                .tapTarget()
        }
        .padding(Theme.Spacing.loose)
        // Primary is the only ink that clears AA over the accent wash, as on
        // every other screen a session draws at rest.
        .foregroundStyle(Theme.Ink.primary)
    }
}
