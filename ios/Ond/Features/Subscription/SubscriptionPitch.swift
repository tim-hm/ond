import OndKit
import OndUI
import SwiftUI

/// The complete önd+ offer, shared by onboarding and the paywall sheet.
///
/// Both surfaces sell the same subscription, so they share the same hierarchy:
/// the free boundary, four connected benefits, two cadence tiles, one purchase
/// action and the privacy promise. The surrounding native chrome still belongs
/// to the caller — onboarding keeps its progress controls and the sheet keeps
/// its dismissal button.
struct SubscriptionPitch: View {
    @Binding var plan: SubscriptionPlan

    /// Whether a missing App Store product turns the action into the way past
    /// the screen. Onboarding must remain completable offline; a paywall opened
    /// deliberately to buy stays a subscription action and names the failure in
    /// `SubscriptionTerms`.
    let continuesWhenUnavailable: Bool

    /// Buys the selected cadence, or continues when the caller permits the
    /// unavailable state to do that.
    let act: () -> Void

    @Environment(SubscriptionStore.self) private var store
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.standard) {
            wordmark
            boundary
            PlusBenefits()
            plans
            purchaseButton
            privacyPromise
            SubscriptionTerms(plan: plan)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// The name and the plus that identifies the connected layer.
    private var wordmark: some View {
        HStack(alignment: .firstTextBaseline, spacing: 0) {
            Text("önd")
                .displaySerif(size: 52)
                .foregroundStyle(Theme.Ink.primary)

            Text("+")
                .displaySerif(size: 26)
                .foregroundStyle(Theme.Breath.inhale)
                .baselineOffset(12)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("önd plus")
    }

    /// The product boundary leads the pitch, before anything that costs money.
    private var boundary: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.close) {
            Text("Everything that works offline stays free. Forever.")
                .displaySerif(size: 30)
                .foregroundStyle(Theme.Ink.primary)
                .accessibilityAddTraits(.isHeader)

            Text(
                "önd+ is only the connected layer. If you never want it, "
                    + "the app is complete without it."
            )
            .font(.callout)
            .foregroundStyle(Theme.Ink.secondary)
        }
    }

    /// Year and month beside each other, in the order the reference reads.
    private var plans: some View {
        planLayout {
            planTile(.yearly)
            planTile(.monthly)
        }
    }

    @ViewBuilder
    private func planLayout(
        @ViewBuilder content: () -> some View
    ) -> some View {
        if dynamicTypeSize.isAccessibilitySize {
            VStack(spacing: Theme.Spacing.close, content: content)
        } else {
            HStack(spacing: Theme.Spacing.close, content: content)
        }
    }

    /// One cadence as a compact price tile. Selection is the reference's quiet
    /// accent wash and ring rather than a radio control added to the content.
    private func planTile(_ candidate: SubscriptionPlan) -> some View {
        let isSelected = candidate == plan

        return Button {
            plan = candidate
        } label: {
            VStack(alignment: .leading, spacing: Theme.Spacing.tight) {
                Text(title(of: candidate))
                    .font(.caption)
                    .foregroundStyle(Theme.Ink.secondary)

                Text(price(of: candidate))
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(Theme.Ink.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)

                Text(detail(of: candidate))
                    .font(.caption)
                    .foregroundStyle(Theme.Ink.tertiary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, minHeight: 66, alignment: .leading)
            .padding(.horizontal, Theme.Spacing.standard)
            .padding(.vertical, Theme.Spacing.close)
            .background {
                ZStack {
                    RoundedRectangle(cornerRadius: Theme.Radius.card)
                        .fill(Theme.Surface.raised.shadow(Theme.Shadow.list))

                    if isSelected {
                        RoundedRectangle(cornerRadius: Theme.Radius.card)
                            .fill(Theme.Accent.brand.opacity(Theme.Fill.selection))
                    }
                }
            }
            .overlay {
                RoundedRectangle(cornerRadius: Theme.Radius.card)
                    .stroke(
                        isSelected
                            ? Theme.Accent.brand.opacity(Self.selectedRing)
                            : Theme.Surface.line,
                        lineWidth: 1
                    )
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel(for: candidate))
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
        .accessibilityIdentifier("paywall-plan-\(candidate.rawValue)")
    }

    /// The same ring strength as the selected goal filters.
    private static let selectedRing = 0.55

    private var purchaseButton: some View {
        Button(action: act) {
            Text(actionTitle)
        }
        .buttonStyle(.inkAction)
        .disabled(store.isBusy)
        .accessibilityLabel(purchaseAccessibilityLabel)
        .accessibilityIdentifier("paywall-purchase")
    }

    /// The line the reference leaves beneath the action: this is private by
    /// construction, whether or not somebody pays.
    private var privacyPromise: some View {
        Text(
            "No account, no ads, no trackers. Your practice history stays on the device "
                + "whether you subscribe or not."
        )
        .font(.caption)
        .foregroundStyle(Theme.Ink.tertiary)
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity)
    }

    private var actionTitle: String {
        if store.offer(for: plan) == .unavailable, continuesWhenUnavailable {
            return "Continue"
        }

        return store.purchaseTitle(for: plan)
    }

    private func title(of candidate: SubscriptionPlan) -> String {
        switch candidate {
        case .monthly: "Monthly"
        case .yearly: "Yearly"
        }
    }

    private func price(of candidate: SubscriptionPlan) -> String {
        store.product(for: candidate)?.displayPrice ?? "—"
    }

    private func detail(of candidate: SubscriptionPlan) -> String {
        switch candidate {
        case .monthly:
            "Cancel any time"
        case .yearly:
            if let equivalent = store.product(for: candidate)?.monthlyEquivalentPrice {
                "\(equivalent) / month"
            } else if let saving = store.annualSaving {
                "Save \(saving)%"
            } else {
                "Billed yearly"
            }
        }
    }

    private func accessibilityLabel(for candidate: SubscriptionPlan) -> String {
        [title(of: candidate), price(of: candidate), detail(of: candidate)]
            .joined(separator: ", ")
    }

    private var purchaseAccessibilityLabel: String {
        guard let product = store.product(for: plan) else { return actionTitle }

        return "\(actionTitle), \(title(of: plan)), \(product.displayPrice) per \(plan.periodName)"
    }
}
