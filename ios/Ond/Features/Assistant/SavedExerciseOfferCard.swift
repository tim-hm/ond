import OndKit
import OndUI
import SwiftUI

/// The coach's offer to keep a pattern as one of the person's own exercises.
///
/// `ExerciseOfferCard`'s shape, with the one difference the action forces: this
/// card has a result. Saving is a network call that can fail, so the button
/// carries three states — offer, saving, saved — rather than dismissing on tap
/// and leaving somebody to go and check.
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
        VStack(alignment: .leading, spacing: Theme.Spacing.close) {
            HStack(alignment: .firstTextBaseline, spacing: Theme.Spacing.standard) {
                VStack(alignment: .leading, spacing: Theme.Spacing.tight) {
                    Text(draft.name)
                        .font(.headline)
                        .foregroundStyle(Theme.Ink.primary)
                    Text(summary)
                        .font(.footnote)
                        .foregroundStyle(Theme.Ink.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                action
            }

            if case let .refused(reason) = stage {
                Text(reason)
                    .font(.footnote)
                    .foregroundStyle(Theme.Accent.caution)
            }
        }
        .padding(Theme.Spacing.standard)
        .glassCard()
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
            Button(saveLabel, action: save)
                .buttonStyle(.borderedProminent)
                .tint(Theme.Accent.brand)
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

    /// The same line the exercise list summarises at — rounds, cycles, rhythm —
    /// so a pattern read here and the same pattern read there describe
    /// themselves identically.
    private var summary: String {
        let roundsPart = "\(draft.rounds) \(draft.rounds == 1 ? "round" : "rounds")"

        guard draft.stages.count == 1, let stage = draft.stages.first else {
            return "\(roundsPart) · \(draft.stages.count) stages"
        }

        let rhythm = stage.phases
            .map(\.duration.inSeconds)
            .joined(separator: "-")
        return "\(roundsPart) · \(stage.cycles) cycles · \(rhythm)"
    }
}
