import OndKit
import OndStyle
import OndUI
import SwiftUI

/// The stop's facts — "relax · 5 min" — in one ink for the surfaces that
/// print them.
///
/// One type for Home's starred rows and the continue card, which had the same
/// view inline, already disagreeing about the weight of the ink. The goal's
/// dot used to live here too; it is `StopRow`'s now, in the gutter the design
/// gives it, and the card deliberately goes without — the facts say the goal
/// in words, so the colour was never the only carrier.
///
/// At `ios/Ond/` rather than inside a feature on `StopStarButton`'s reasoning:
/// two features draw it and neither owns it, and it cannot go on to `OndUI`,
/// which knows nothing about a `DialStop` and must not learn.
struct StopFactsLine: View {
    let stop: DialStop
    let tier: SubscriptionTier

    var body: some View {
        Text(stop.facts(for: tier))
            .font(.subheadline)
            .foregroundStyle(Theme.Ink.secondary)
    }
}
