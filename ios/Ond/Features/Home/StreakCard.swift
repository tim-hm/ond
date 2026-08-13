import OndKit
import OndUI
import SwiftUI

/// Where a practice stands: the stage it has reached, the run it is on, and what
/// the run is for.
///
/// App-side rather than in `OndUI`, and that is the module boundary rather than
/// an oversight: this takes a `JourneyStats`, and `OndUI` knows nothing about the
/// domain and must not learn. `StatTile` beside it carries a number and a word,
/// which is why that one could go the other way.
///
/// Every sentence on it is `JourneyStats`', not this file's. The product's copy
/// rule is a rule — celebrate consistency, never pressure — so it lives beside
/// the numbers it reads, where a test can pin it.
struct StreakCard: View {
    let stats: JourneyStats

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.close) {
            // Above the streak, so a paused one still has something standing
            // over it.
            if let stage = stats.stage {
                Text(stage.title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Theme.Ink.secondary)
            }

            Text(stats.streakHeadline)
                .font(.title2.weight(.semibold))

            Text(stats.streakDetail)
                .font(.callout)
                .foregroundStyle(Theme.Ink.secondary)

            Text(JourneyStats.daysDetail)
                .font(.caption)
                .foregroundStyle(Theme.Ink.tertiary)
                .padding(.top, Theme.Spacing.tight)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Theme.Spacing.loose)
        .background(
            Theme.Accent.brand.opacity(0.12),
            in: RoundedRectangle(cornerRadius: Theme.Radius.card)
        )
        .accessibilityElement(children: .combine)
    }
}
