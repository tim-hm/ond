import OndKit
import OndUI
import SwiftUI

/// One subscription, at two prices, and the links App Review will not approve a
/// paywall without.
///
/// The contextual headline answers why this sheet opened; the four benefits
/// answer what the subscription adds. Nothing else makes the person read the
/// same offer twice before choosing how often to be billed.
struct PaywallView: View {
    @Environment(\.dismiss) private var dismiss

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    /// From the environment, like `SessionSettings`: `OndApp` owns the one
    /// instance, and the surfaces that offer a subscription are nowhere near it.
    @Environment(SubscriptionStore.self) private var store

    /// What the person just ran into, which decides the headline and nothing
    /// else — see `PaywallContext`.
    private let context: PaywallContext

    /// Which cadence the buy button buys. Yearly by default: it is the better
    /// deal, it is the one the badge points at, and a monthly default would be
    /// the app quietly steering somebody towards paying more.
    @State private var plan: SubscriptionPlan = .yearly

    init(_ context: PaywallContext = .general) {
        self.context = context
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Spacing.loose) {
                    header
                    PlusBenefits()
                    plans
                    purchaseButton
                    SubscriptionTerms(plan: plan)
                }
                .padding(Theme.Spacing.standard)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(Theme.Surface.ground)
            .navigationTitle("önd+")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
            // Dismisses itself once the subscription is theirs, rather than
            // leaving them looking at a paywall for something they now own.
            .onChange(of: store.tier) { _, tier in
                if tier >= context.requires {
                    dismiss()
                }
            }
            .task { await store.loadProducts() }
        }
    }

    private var header: some View {
        Text(context.headline)
            .font(.title2.weight(.semibold))
            .foregroundStyle(Theme.Ink.primary)
            .accessibilityAddTraits(.isHeader)
    }

    private var plans: some View {
        VStack(spacing: Theme.Spacing.close) {
            ForEach(SubscriptionPlan.allCases, id: \.self) { plan in
                planRow(plan)
            }
        }
    }

    private var purchaseButton: some View {
        Button {
            Task { await store.purchase(plan) }
        } label: {
            Text(callToAction).primaryActionLabel()
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
        .tint(Theme.Accent.brand)
        .disabled(store.isBusy || isHeld)
        .accessibilityLabel(purchaseAccessibilityLabel)
    }

    /// One cadence, as a glass row somebody chooses between rather than a
    /// segmented control: the yearly row carries a saving line, and a segment
    /// has nowhere to put one.
    private func planRow(_ candidate: SubscriptionPlan) -> some View {
        let isSelected = candidate == plan

        return Button {
            plan = candidate
        } label: {
            HStack(alignment: dynamicTypeSize.isAccessibilitySize ? .top : .center) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(isSelected ? Theme.Accent.brand : Theme.Ink.tertiary)
                    .frame(width: Theme.Spacing.loose)
                    .accessibilityHidden(true)

                if dynamicTypeSize.isAccessibilitySize {
                    verticalPlanLabel(candidate, isSelected: isSelected)
                } else {
                    ViewThatFits(in: .horizontal) {
                        horizontalPlanLabel(candidate, isSelected: isSelected)
                        verticalPlanLabel(candidate, isSelected: isSelected)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, Theme.Spacing.standard)
            .padding(.vertical, Theme.Spacing.close)
            .tapTarget()
        }
        .buttonStyle(.plain)
        .glassCard(tinted: isSelected ? Theme.Accent.brand : nil, interactive: true)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel(for: candidate))
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }

    private func horizontalPlanLabel(
        _ candidate: SubscriptionPlan,
        isSelected: Bool
    ) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: Theme.Spacing.close) {
            Text(title(of: candidate))
                .font(.subheadline.weight(isSelected ? .semibold : .regular))
                .foregroundStyle(Theme.Ink.primary)

            saving(for: candidate)

            Spacer(minLength: Theme.Spacing.close)

            Text(price(of: candidate))
                .font(.subheadline.weight(.medium))
                .foregroundStyle(Theme.Ink.secondary)
        }
    }

    private func verticalPlanLabel(
        _ candidate: SubscriptionPlan,
        isSelected: Bool
    ) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.tight) {
            Text(title(of: candidate))
                .font(.subheadline.weight(isSelected ? .semibold : .regular))
                .foregroundStyle(Theme.Ink.primary)

            saving(for: candidate)

            Text(price(of: candidate))
                .font(.subheadline.weight(.medium))
                .foregroundStyle(Theme.Ink.secondary)
        }
    }

    @ViewBuilder
    private func saving(for candidate: SubscriptionPlan) -> some View {
        if candidate == .yearly, let saving = store.annualSaving {
            Text("Save \(saving)%")
                .font(.caption.weight(.semibold))
                .foregroundStyle(Theme.Accent.brand)
        }
    }

    /// Whether this person already holds what they came here for — the one
    /// question this screen asks about the tier, read against the context's own
    /// lever rather than against a rung typed in here.
    private var isHeld: Bool {
        store.tier >= context.requires
    }

    /// "Try 7 days free" only where there is a trial on the *selected* plan
    /// that this person can actually take — see `SubscriptionStore.offer(for:)`,
    /// which the trial step in onboarding reads the same words out of.
    private var callToAction: String {
        guard !isHeld else { return "Your plan" }

        return store.purchaseTitle(for: plan)
    }

    private func title(of plan: SubscriptionPlan) -> String {
        switch plan {
        case .monthly: "Monthly"
        case .yearly: "Yearly"
        }
    }

    /// The price comes from the App Store or not at all: it varies by
    /// storefront, and a hardcoded amount would be wrong in most countries and
    /// illegal in a few. A missing one reads as a blank rather than a guess —
    /// somebody with no signal can still see what the subscription is and buy it
    /// when the sheet loads.
    private func price(of plan: SubscriptionPlan) -> String {
        guard let product = store.product(for: plan) else { return " " }

        return "\(product.displayPrice) / \(plan.periodName)"
    }

    private func accessibilityLabel(for plan: SubscriptionPlan) -> String {
        var parts = [title(of: plan)]
        if plan == .yearly, let saving = store.annualSaving {
            parts.append("Save \(saving) percent")
        }
        if let product = store.product(for: plan) {
            parts.append("\(product.displayPrice) per \(plan.periodName)")
        }
        return parts.joined(separator: ", ")
    }

    private var purchaseAccessibilityLabel: String {
        guard let product = store.product(for: plan) else { return callToAction }

        return "\(callToAction), \(title(of: plan)), \(product.displayPrice) per \(plan.periodName)"
    }
}
