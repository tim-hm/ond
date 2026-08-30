import OndKit
import OndUI
import SwiftUI

/// A moment as a card, with the one tap that breathes it. The title is the
/// occasion, so the mechanics line carries the news of which exercise it
/// resolves to. The goal is a chip, not a dot: a word beside a colour keeps
/// five near accents legible. The tap, spoken label and star are
/// `StartableStopCard`'s; the glass is this view's.
struct MomentCard: View {
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
                        EvidenceChip(grade: grade)
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
