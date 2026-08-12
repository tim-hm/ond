import OndKit
import OndStyle
import OndUI
import SwiftUI

/// One thing somebody keeps in front of them, at row height.
///
/// The vocabulary the board's pinned row had — the goal wash, the facts, the
/// star — in the one shape Home has left. What it drops is the `Reason`
/// plumbing: the board dealt every stop it held and needed a line per card
/// saying why that one was there, and a shelf holds only what was starred, which
/// is a reason nobody has to be told.
///
/// It carries the length and what the exercise is for, because a shelf that
/// dropped them would make Home the place you learn least about the exercises
/// you care most about.
struct StarredStopRow: View {
    let stop: DialStop
    let tier: SubscriptionTier
    let isStarred: Bool
    let star: () -> Void
    let start: () -> Void

    var body: some View {
        HStack(spacing: Theme.Spacing.standard) {
            Button(action: start) {
                VStack(alignment: .leading, spacing: 0) {
                    Text(stop.title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Theme.Ink.primary)
                        .lineLimit(1)

                    Text(stop.facts(for: tier))
                        .font(.caption)
                        .foregroundStyle(Theme.Ink.secondary)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            // Spoken whole, because a label on a button replaces every label
            // composed under it — including the "· Plus" and "· on your watch"
            // marks the caption carries for a sighted reader.
            .accessibilityLabel(stop.spokenLabel(for: tier))
            .accessibilityHint("Starts the session")

            StopStarButton(stop: stop, isStarred: isStarred, star: star)
        }
        .padding(.leading, Theme.Spacing.standard)
        .padding(.vertical, Theme.Spacing.close)
        .background(
            stop.goal.accent.opacity(0.12),
            in: .rect(cornerRadius: Theme.Radius.card)
        )
    }
}
