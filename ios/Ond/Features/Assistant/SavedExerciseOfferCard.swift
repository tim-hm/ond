import OndKit
import OndUI
import SwiftUI

/// The coach's offer to keep a pattern as one of the person's own exercises.
///
/// `OfferCard`'s shell, with the one difference the action forces: this card
/// has a result. Saving is a network call that can fail, so the button carries
/// three states — offer, saving, saved — rather than dismissing on tap and
/// leaving somebody to go and check.
///
/// A refusal is reported here rather than thrown upwards, for the reason
/// `UserTechniqueModel.save` throws in the first place: the transcript is a
/// conversation, and dropping it to an error screen over a card would take away
/// the answer the person was reading.
struct SavedExerciseOfferCard: View {
    let draft: TechniqueDraft
    let own: UserTechniqueModel

    @State private var stage: Stage = .offered

    /// Named for the shape rather than `State`, which would shadow the property
    /// wrapper this view declares one with.
    private enum Stage: Equatable {
        case offered
        case saving
        case saved
        case refused(String)
    }

    var body: some View {
        OfferCard(
            eyebrow: "Keep this",
            title: draft.name,
            summary: draft.offerSummary,
            goal: draft.goal
        ) {
            VStack(alignment: .leading, spacing: Theme.Spacing.close) {
                action

                if case let .refused(reason) = stage {
                    Text(reason)
                        .font(.footnote)
                        .foregroundStyle(Theme.Accent.caution)
                }
            }
        }
    }

    @ViewBuilder
    private var action: some View {
        switch stage {
        case .saved:
            // A label rather than a disabled button: the exercise is theirs now,
            // and a greyed-out Save reads as something that failed.
            Label("Saved", systemImage: "checkmark")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(Theme.Ink.secondary)
                .labelStyle(.titleAndIcon)
        case .saving:
            ProgressView()
        case .offered, .refused:
            // Glass rather than the filled ink an exercise offer's Begin takes:
            // saving a pattern is the smaller of the two things a card can
            // offer, and two filled buttons in one transcript would compete.
            Button(saveLabel, action: save)
                .buttonStyle(.glass)
        }
    }

    /// "Try again" after a refusal, because the same word twice on a button that
    /// visibly did not work reads as a button that does nothing.
    private var saveLabel: String {
        if case .refused = stage {
            "Try again"
        } else {
            "Save"
        }
    }

    private func save() {
        stage = .saving
        Task {
            do {
                try await own.save(draft)
                stage = .saved
            } catch {
                stage = .refused(error.localizedDescription)
            }
        }
    }
}
