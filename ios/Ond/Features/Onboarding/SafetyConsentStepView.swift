import OndKit
import OndUI
import SwiftUI

/// The safety terms, and the last screen before anybody breathes.
///
/// This is what replaced a caution on every exercise card and detail screen. It
/// is a wall on purpose, in a flow whose every other step can be passed by: the
/// hazards are unrelated to each other and there is no longer anywhere else the
/// app says them, so the one screen that does has to be met rather than
/// scrolled past. `OnboardingModel` withholds Skip and Back here for the same
/// reason, and the forward button carries the agreement's own words.
///
/// The copy is `SafetyConsent`'s, not this view's. What is rendered and what is
/// recorded have to be the same words, and a literal typed into a `Text` here
/// would be a third copy nobody keeps in step.
///
/// On the ground rather than in a card, which is the one place in this flow the
/// glass is wrong: every other card holds something to answer, and framing the
/// terms the same way makes them one more panel to get past. These are what the
/// screen is.
struct SafetyConsentStepView: View {
    let terms: SafetyConsent

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.loose) {
            VStack(alignment: .leading, spacing: Theme.Spacing.close) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 19))
                    .foregroundStyle(Theme.Accent.caution)
                    .accessibilityHidden(true)

                Text(terms.title)
                    .displaySerif(size: 36)
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

    /// Keeps the wall readable on wide phones while narrow screens continue to
    /// use every point inside the page margins.
    private static let readingWidth: CGFloat = 340
}
