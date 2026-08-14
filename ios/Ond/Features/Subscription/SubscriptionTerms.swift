import OndKit
import OndUI
import SwiftUI

/// The small print App Review will not approve an offer without: what a
/// purchase renews at, Restore Purchases, and the two documents.
///
/// Its own view because there are now two surfaces that sell önd+ — the paywall
/// sheet and the trial step in onboarding — and the 3.1.2 disclosure has to be
/// identical on both. Two copies of a sentence composed from a price is two
/// chances for one of them to keep saying seven days after the offer changes.
///
/// Draws no background of its own. Both purchase surfaces place it directly
/// beneath the offer, so it stays attached to the price it describes and moves
/// with that content at larger text sizes.
struct SubscriptionTerms: View {
    /// Which cadence the terms describe. Every sentence here is about a
    /// specific purchase, so there is no sensible answer without one.
    let plan: SubscriptionPlan

    @Environment(SubscriptionStore.self) private var store

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        VStack(spacing: Theme.Spacing.close) {
            if store.isAwaitingApproval {
                Text("Waiting for approval. You'll get it as soon as that comes through.")
                    .font(.footnote)
                    .foregroundStyle(Theme.Ink.secondary)
                    .multilineTextAlignment(.center)
            }

            // The one purchase failure worth a line on screen, because it is the
            // one a person cannot read from the button: nothing happened, and
            // trying again will not change that. Says what it cost rather than
            // why it failed — the cause is the developer's, and the log carries
            // it.
            if store.isUnavailable {
                Text("This isn't on sale right now. Nothing was charged.")
                    .font(.footnote)
                    .foregroundStyle(Theme.Ink.secondary)
                    .multilineTextAlignment(.center)
            }

            Text(renewalTerms)
                .font(.caption)
                .foregroundStyle(Theme.Ink.tertiary)
                .multilineTextAlignment(.center)

            legalLinkLayout {
                Button("Restore Purchases") {
                    Task { await store.restore() }
                }
                .disabled(store.isBusy)
                .tapTarget()

                Link("Privacy", destination: LegalLinks.privacyPolicy)
                    .tapTarget()
                Link("Terms", destination: LegalLinks.termsOfUse)
                    .tapTarget()
            }
            .font(.footnote)
            .tint(Theme.Accent.brand)
        }
    }

    /// What App Review's guideline 3.1.2 requires beside an offer: the length of
    /// the trial, the price that follows it, how often it recurs, and that it
    /// can be cancelled. Composed from the App Store's own price so it is right
    /// in every storefront, and it drops the trial clause where there is no
    /// trial on offer rather than promising one this person cannot take.
    private var renewalTerms: String {
        let tail = "Renews automatically; cancel in Settings."

        return switch store.offer(for: plan) {
        case .unavailable:
            tail
        case let .paid(price):
            "\(price)/\(plan.periodName). \(tail)"
        case let .trial(days, price):
            "\(days) days free, then \(price)/\(plan.periodName). \(tail)"
        }
    }

    private var legalLinkLayout: AnyLayout {
        if dynamicTypeSize.isAccessibilitySize {
            AnyLayout(VStackLayout(spacing: Theme.Spacing.close))
        } else {
            AnyLayout(HStackLayout(spacing: Theme.Spacing.standard))
        }
    }
}
