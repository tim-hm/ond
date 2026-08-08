import OndKit
import SwiftUI

/// What the exercise is called, what it is for, and when to reach for it — the
/// three answers that are about the exercise rather than about the breath.
///
/// Both text fields truncate against the server's own ceiling as they are typed
/// rather than refusing on save, for the reason every dial below them is bounded
/// by `AuthoringLimits`: nobody should be told no by a screen that could have
/// said so while they were still writing.
struct TechniqueAboutSection: View {
    @Binding var draft: TechniqueDraft
    let limits: AuthoringLimits

    var body: some View {
        Section {
            TextField("Name", text: $draft.name)
                .onChange(of: draft.name) { _, name in
                    // Trimmed on save, so the ceiling counts what the server
                    // will: a name that is only over the limit because of
                    // trailing spaces should not block the button.
                    draft.name = String(name.prefix(limits.maxNameChars))
                }

            Picker("For when you want to", selection: $draft.goal) {
                ForEach(TechniqueGoal.allCases, id: \.self) { goal in
                    Text(goal.intentObject).tag(goal)
                }
            }

            // Vertical, because what belongs here is a sentence rather than a
            // label — and absent from the composer's completeness check, because
            // an exercise nobody has described is a whole exercise.
            TextField("What it's for (optional)", text: $draft.summary, axis: .vertical)
                .lineLimit(1 ... 4)
                .onChange(of: draft.summary) { _, summary in
                    draft.summary = String(summary.prefix(limits.maxSummaryChars))
                }
        } footer: {
            Text(
                "The name is yours — it is what the exercise is called everywhere in the app. "
                    + "What it's for shows beneath it, the way the app's own exercises describe "
                    + "themselves."
            )
        }
    }
}
