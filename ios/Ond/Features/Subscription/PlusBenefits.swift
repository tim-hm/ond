import OndUI
import SwiftUI

/// What önd+ opens, in the person's terms — four rows, one per thing that costs
/// something to serve, each stating its own limit underneath.
///
/// A view rather than a list of strings on each screen that draws it. The
/// paywall and onboarding's trial step make the same promise, and a second copy
/// is a second thing to keep true when a gate moves — which is exactly what
/// `SubscriptionTier`'s named levers exist to prevent one level down.
///
/// **Every row says what it will not do.** A benefit list is where a wellness
/// app usually stops being careful, and the limits are the part this one cannot
/// afford to leave to the small print: the coach does not diagnose, the board is
/// off until you name yourself, the trends are never a readiness score. Somebody
/// deciding whether to pay should meet the boundary here rather than discover it
/// afterwards.
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
        .glassCard()
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
        .padding(Theme.Spacing.standard)
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

        /// The dot's colour, defaulted because only one row has a reason to
        /// differ: the board takes hold, since it is the one benefit that
        /// involves other people — a difference in kind rather than in degree,
        /// which is the only thing colour should ever be spent on here.
        ///
        /// A `var` so the memberwise initialiser keeps it: a `let` with a
        /// default is not something the caller may set, so Swift drops it from
        /// the parameter list and the one row that overrides it stops compiling.
        var mark: Color = Theme.Breath.inhale

        var id: String {
            title
        }
    }

    private static let benefits = [
        Benefit(
            title: "Coach informed by your goals and practice",
            limit: "Answers from what you have breathed. It doesn't diagnose anything."
        ),
        Benefit(
            title: "Global and age-band leaderboards",
            limit: "Off until you put a name to it, and it ranks what you did — "
                + "never how calm anybody got.",
            mark: Theme.Breath.hold
        ),
        Benefit(
            title: "Breathing, heart-rate and HRV trends",
            limit: "What your watch measured, and your heart around each practice. "
                + "No readiness score, ever."
        ),
        // Names the order rather than "connected Watch practice", which reads as
        // wrist sessions reaching your journey — free, and always was.
        Benefit(
            title: "Send a session to your Watch, with live heart rate",
            limit: "The reading is drawn while it plays and never stored or shared."
        ),
    ]
}
