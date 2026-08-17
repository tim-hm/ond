import OndKit
import OndStyle
import OndUI
import SwiftUI

/// The goal's dot and the stop's facts — "relax · 5 min", behind a 6pt mark of
/// the goal's accent.
///
/// One type for the surfaces that print it — Home's starred rows and the
/// continue card — which had the same two views inline, already disagreeing
/// about the weight of the ink. The dot is the goal's one mark on the row, and
/// the facts beside it say the same thing in words, so the colour is never the
/// only carrier.
///
/// At `ios/Ond/` rather than inside a feature on `StopStarButton`'s reasoning:
/// two features draw it and neither owns it, and it cannot go on to `OndUI`,
/// which knows nothing about a `DialStop` and must not learn.
struct StopFactsLine: View {
    let stop: DialStop
    let tier: SubscriptionTier

    var body: some View {
        HStack(spacing: Theme.Spacing.close) {
            Circle()
                .fill(stop.goal.accent)
                .frame(width: 6, height: 6)

            Text(stop.facts(for: tier))
                .font(.subheadline)
                .foregroundStyle(Theme.Ink.secondary)
        }
    }
}
