import OndKit
import OndUI
import SwiftUI

/// The one place önd asks for money, offered once and passed by with "Not now".
///
/// It sits after the answers are saved, which is what makes the offer safe to
/// refuse: somebody who quits here has still finished onboarding, and a relaunch
/// puts them on the safety terms rather than back at the first question.
///
/// One plan and no picker, unlike the paywall. This is a screen somebody
/// arrived at on the way to breathing rather than one they opened to buy
/// something, and a monthly-or-yearly decision in front of a person who has not
/// yet decided they want either is a choice charged for nothing. "See plans"
/// opens the real paywall for anybody who does want to choose — the year is
/// where the saving is, and it should be a tap away rather than hidden.
///
/// The primary button is `OnboardingView`'s, in the bottom inset with every
/// other step's: it is what buys the plan named here, so the two read the same
/// offer through `SubscriptionStore.trialPlan`.
struct TrialStepView: View {
    @Environment(SubscriptionStore.self) private var store

    @State private var isShowingPaywall = false

    var body: some View {
        OnboardingQuestion(title: title, subtitle: subtitle) {
            offer

            Button("See plans") {
                isShowingPaywall = true
            }
            .font(.footnote)
            .tint(Theme.Accent.brand)
            .frame(maxWidth: .infinity)

            SubscriptionTerms(plan: store.trialPlan)
                .padding(.top, Theme.Spacing.close)
        }
        .paywall(for: .general, isPresented: $isShowingPaywall)
        // The prices come from the App Store, and nothing before this screen
        // has any reason to have asked for them.
        .task { await store.loadProducts() }
    }

    /// The headline asks the group-wide question — is a trial being offered at
    /// all — which is what `SubscriptionStore.trialDays` answers and this is
    /// its one caller. Everything with a price beside it reads `trialPlan`'s
    /// own offer instead, and `trialPlan` is chosen so the two agree.
    private var title: String {
        guard let days = store.trialDays else { return "önd+" }

        return "önd+, free for \(days) days"
    }

    private var subtitle: String {
        "önd works without it. This is the part that needs a server behind it."
    }

    private var offer: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.standard) {
            PlusBenefits()

            if let price {
                Text(price)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(Theme.Ink.primary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Theme.Spacing.standard)
        .glassCard(tinted: Theme.Accent.brand)
    }

    /// The price comes from the App Store or not at all: it varies by
    /// storefront, and a hardcoded amount would be wrong in most countries and
    /// illegal in a few. Absent while the prices are still in the air, or with
    /// no signal at all — which is the state this screen degrades into, where
    /// the button says Continue and nothing here promises anything.
    private var price: String? {
        let plan = store.trialPlan
        guard let product = store.product(for: plan) else { return nil }

        let period = plan == .monthly ? "month" : "year"
        guard let days = store.trialDays(for: plan) else {
            return "\(product.displayPrice) a \(period)."
        }

        return "Free for \(days) days, then \(product.displayPrice) a \(period)."
    }
}
