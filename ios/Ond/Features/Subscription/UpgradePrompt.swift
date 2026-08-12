import OndKit
import OndUI
import SwiftUI

/// One line offering the subscription, wherever the free tier has just met its
/// edge.
///
/// Draws nothing at all for a subscriber, so a caller never has to branch: the
/// condition lives here, in one place, rather than in every surface that could
/// mention a subscription. The affordance is a line of text and a tap, not a
/// banner — this appears next to something somebody is reading, and a card
/// would take the screen away from what they came for.
struct UpgradePrompt: View {
    /// What just happened, in the caller's own words. Passed in rather than
    /// fixed here because "today's answers are from the rules" and "your trends
    /// stay on this phone" are different moments, and one generic sentence
    /// would be honest about neither.
    let reason: String

    /// What they ran into, which decides the headline of the sheet this opens.
    let context: PaywallContext

    @Environment(SubscriptionStore.self) private var store

    @State private var isShowingPaywall = false

    init(reason: String, for context: PaywallContext) {
        self.reason = reason
        self.context = context
    }

    var body: some View {
        if store.tier < context.requires {
            Button {
                isShowingPaywall = true
            } label: {
                HStack(spacing: Theme.Spacing.tight) {
                    Text(reason)
                        .foregroundStyle(Theme.Ink.secondary)
                    Text(SubscriptionTier.plus.title)
                        .foregroundStyle(Theme.Accent.brand)
                    Image(systemName: "chevron.right")
                        .font(.caption2)
                        .foregroundStyle(Theme.Accent.brand)
                        // As on the journey cards: the button already announces
                        // itself, and the chevron only says so to the eye.
                        .accessibilityHidden(true)
                }
                .font(.footnote)
                .multilineTextAlignment(.leading)
            }
            .buttonStyle(.plain)
            .paywall(for: context, isPresented: $isShowingPaywall)
        }
    }
}
