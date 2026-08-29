import OndKit
import OndUI
import SwiftUI

/// A moment, as a card: what it is called, the exercise it prescribes, the
/// register and evidence behind it, and the one tap that breathes it.
///
/// Titled by the occasion — "Before a presentation", "Awake at three" — so
/// the moment is the name and the exercise it resolves to is genuinely news,
/// which is what the mechanics line under the title carries. The tap, the
/// spoken label and the star are `StartableStopCard`'s; the glass is this
/// one's, because the shell has no opinion about the material.
///
/// The goal's chip rather than a dot. A card has room for the word, and a
/// word beside a colour is what makes five accents that walk one arc of the
/// wheel legible as five different things.
struct ProtocolCard: View {
    let stop: DialStop
    let tier: SubscriptionTier

    let start: () -> Void

    var body: some View {
        StartableStopCard(stop: stop, tier: tier, start: start) {
            VStack(alignment: .leading, spacing: Theme.Spacing.close) {
                Text(stop.title)
                    .font(.title3.weight(.semibold))
                    // The spec tracks card titles −2%; of 20pt.
                    .tracking(-0.4)
                    .foregroundStyle(Theme.Ink.primary)

                Text(stop.mechanics(for: tier))
                    .font(.subheadline)
                    .foregroundStyle(Theme.Ink.tertiary)

                HStack(spacing: Theme.Spacing.close) {
                    GoalBadge(goal: stop.goal)

                    if let grade = stop.technique.evidenceGrade {
                        EvidenceChip(grade: grade, includesSubject: true)
                    }
                }
                .padding(.top, Theme.Spacing.tight)
            }
        }
        // Interactive because the card is itself the button: the glass answers
        // a press with the material's own flex, which a flat fill never could.
        .glassCard(interactive: true)
    }
}
