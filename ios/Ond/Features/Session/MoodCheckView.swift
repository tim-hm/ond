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
/// charged an extra tap for having an opinion or for not having one. The
/// answer is written to Health before the countdown starts rather than
/// alongside it — the first write of an install brings the system's own sheet
/// with it, and a session counting down behind a modal is a session nobody
/// asked to have started.
struct MoodCheckView: View {
    /// Records the answer and then lets the session begin. Async because the
    /// gap between the two is exactly the write above.
    let onAnswer: (Mood) async -> Void

    let onSkip: () -> Void

    /// The tap, held so the scale fills in the instant it lands rather than
    /// when the write comes back. Also the guard against a second tap during
    /// that gap — a mood is answered once.
    @State private var chosen: Mood?

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

            MoodScale(selection: chosen) { mood in
                guard chosen == nil else { return }
                chosen = mood
                Task { await onAnswer(mood) }
            }

            Spacer()

            Button("Skip", action: onSkip)
                .font(.subheadline)
                .frame(minHeight: 44)
        }
        .padding(Theme.Spacing.loose)
        // Primary is the only ink that clears AA over the accent wash, as on
        // every other screen a session draws at rest.
        .foregroundStyle(Theme.Ink.primary)
    }
}
