import OndKit
import OndUI
import SwiftUI

/// The safety terms, and the last screen before anybody breathes. A wall on
/// purpose: it replaced a caution on every exercise card, so no other screen
/// says the hazards — `OnboardingModel` withholds Skip and Back here, and the
/// forward button carries the agreement's own words. The copy is
/// `SafetyConsent`'s: what is rendered and what is recorded must be the same words.
struct SafetyConsentStepView: View {
    let terms: SafetyConsent

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.loose) {
            VStack(alignment: .leading, spacing: Theme.Spacing.close) {
                CautionRule(width: 48).padding(.bottom, 4)

                Text(terms.title)
                    .displaySerif(size: 42)
                    .foregroundStyle(Theme.Ink.primary)

                Text(terms.intro)
                    .font(.body)
                    .foregroundStyle(Theme.Ink.secondary)
                    .lineSpacing(3)
                    .padding(.top, Theme.Spacing.tight)
                    .frame(maxWidth: Self.readingWidth, alignment: .leading)
            }
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isHeader)

            VStack(alignment: .leading, spacing: 0) {
                Divider().overlay(Theme.Surface.line)

                ForEach(terms.points.indices, id: \.self) { index in
                    Text(terms.points[index])
                        .font(.callout)
                        .foregroundStyle(Theme.Ink.primary)
                        .lineSpacing(3)
                        .frame(maxWidth: Self.readingWidth, alignment: .leading)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 14)

                    Divider().overlay(Theme.Surface.line)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// The wall's own page margin, wider than every other screen's, read by
    /// both containers that show it. Here rather than in `Theme.Spacing`: it
    /// is this screen's measurement, not a sixth step in a scale the rest of
    /// the app would then reach for.
    static let margin: CGFloat = 32

    /// Keeps the wall readable on wide phones while narrow screens continue to
    /// use every point inside the page margins.
    private static let readingWidth: CGFloat = 340
}
