import OndUI
import SwiftUI

/// What önd+ opens — four rows, each stating its own limit underneath. One
/// view because the paywall and onboarding's trial step make the same promise,
/// and a second copy is a second thing to keep true when a gate moves. Every
/// row says what it will not do: somebody deciding whether to pay should meet
/// the boundary here rather than discover it afterwards.
struct PlusBenefits: View {
    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(Self.benefits.enumerated()), id: \.element.id) { index, benefit in
                if index > 0 {
                    Divider().overlay(Theme.Surface.line)
                }

                row(benefit)
            }
        }
        .background {
            RoundedRectangle(cornerRadius: Theme.Radius.card)
                .fill(Theme.Surface.raised.shadow(Theme.Shadow.list))
        }
        .overlay {
            RoundedRectangle(cornerRadius: Theme.Radius.card)
                .stroke(Theme.Surface.line, lineWidth: 0.5)
        }
    }

    private func row(_ benefit: Benefit) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: Theme.Spacing.close) {
            Circle()
                .fill(benefit.mark)
                .frame(width: 6, height: 6)
                // Nudged onto the middle of the first line rather than sitting
                // under its baseline — `SessionHistoryRow` places its goal dot
                // the same way.
                .alignmentGuide(.firstTextBaseline) { $0.height }
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: Theme.Spacing.tight) {
                Text(benefit.title)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(Theme.Ink.primary)

                Text(benefit.limit)
                    .font(.caption)
                    .foregroundStyle(Theme.Ink.tertiary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, Theme.Spacing.standard)
        .padding(.vertical, Theme.Spacing.close + Theme.Spacing.tight)
        // One element per row: the title and its limit are one sentence about
        // one thing, and hearing them as two is hearing a promise and then,
        // separately, a caveat about nothing.
        .accessibilityElement(children: .combine)
    }

    private struct Benefit: Identifiable {
        let title: String
        /// What this one deliberately does not do, in the same breath as what it
        /// does.
        let limit: String

        /// The dot's colour. Only the leaderboard row differs — the one
        /// benefit that is not a connected feature. It takes the quietest ink
        /// rather than `Breath.hold`, which means a hold wherever it appears
        /// and so is not available as a category bullet. A `var` so the
        /// memberwise initialiser keeps it.
        var mark: Color = Theme.Breath.inhale

        var id: String {
            title
        }
    }

    private static let benefits = [
        Benefit(
            title: "A coach who reads your notes",
            limit: "Answers in text. Doesn't diagnose anything."
        ),
        Benefit(
            title: "Phone and watch in one session",
            limit: "Haptics on the wrist, geometry on the phone."
        ),
        Benefit(
            title: "Health trends over months",
            limit: "Ranges and counts. No readiness score, ever."
        ),
        Benefit(
            title: "Leaderboards, if you want them",
            limit: "Off by default. Minutes practised, nothing ranked by calm.",
            mark: Theme.Ink.tertiary
        ),
    ]
}
