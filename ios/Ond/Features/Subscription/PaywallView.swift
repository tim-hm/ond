import OndKit
import OndUI
import SwiftUI

/// One subscription, at two prices, and the links App Review will not approve a
/// paywall without.
///
/// The contextual headline answers why this sheet opened, the boundary answers
/// what stays free whatever they decide, and the four benefits answer what the
/// subscription adds. Nothing else makes the person read the same offer twice
/// before choosing how often to be billed.
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
            GeometryReader { viewport in
                ScrollView {
                    // One spacer, not two. Two split the slack on a tall phone
                    // and float the headline a third of the way down the sheet;
                    // one sends all of it between the description and the
                    // controls, which anchors this the way an onboarding step
                    // is anchored — heading at the top, the thing you tap at
                    // the bottom.
                    VStack(alignment: .leading, spacing: 0) {
                        description
                        Spacer(minLength: Theme.Spacing.loose)
                        purchaseControls
                    }
                    .padding(Theme.Spacing.standard)
                    .frame(
                        maxWidth: .infinity,
                        minHeight: viewport.size.height,
                        alignment: .leading
                    )
                }
                .scrollBounceBehavior(.basedOnSize)
            }
            .background(Theme.Surface.ground)
            // No title: the wordmark below is the sheet's own masthead, and a
            // bar repeating it put the name on screen twice, six points apart.
            // Home hides its bar for the same reason; here the bar has to stay
            // for the dismissal to have somewhere to sit.
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                // Trailing rather than the cancellation slot, and worded as a
                // refusal somebody is entitled to make rather than as a window
                // being closed. It is the same dismissal either way; what
                // changes is whether the sheet reads as an offer or a demand.
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Not now") { dismiss() }
                }
            }
            .sensoryFeedback(.success, trigger: isHeld)
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

    /// The name, and the plus that is the whole subject of the sheet.
    ///
    /// Lowercase and never uppercased, as everywhere else the wordmark appears:
    /// the name is önd, and ÖND is a different word wearing its hat.
    private var wordmark: some View {
        HStack(alignment: .firstTextBaseline, spacing: 0) {
            Text("önd")
                .displaySerif(size: 52)
                .foregroundStyle(Theme.Ink.primary)

            Text("+")
                .displaySerif(size: 26)
                .foregroundStyle(Theme.Breath.inhale)
                // Lifted off the shared baseline, or half the size of the word
                // beside it reads as a subscript rather than as part of the
                // mark.
                .baselineOffset(12)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("önd plus")
    }

    /// Why this sheet opened, which is the one thing on it that changes.
    ///
    /// Smaller than the boundary below it, and deliberately: what somebody ran
    /// into is the reason they are reading, but it is not the argument. The
    /// argument is that they can decline.
    ///
    /// **Ink rather than the accent the refresh draws it in.** `Breath.inhale`
    /// holds `Accent.brand`'s light value, which is pinned to the icon ring at
    /// `#2E7E96` and measures 4.01:1 on the light ground — under the 4.5:1 floor
    /// for text this size, with no large-text allowance at 15pt. Weight and
    /// position separate it from the boundary's detail line instead; the colour
    /// was carrying no information the size did not already carry.
    private var header: some View {
        Text(context.headline)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(Theme.Ink.secondary)
    }

    /// The line this app would rather be judged on than any benefit.
    ///
    /// A paywall's job is to sell, and the honest version of that here is to say
    /// where the paying stops before saying what it buys. Everything that works
    /// without a server is free and stays free; what önd+ opens is the connected
    /// layer and nothing else. Somebody who reads this and closes the sheet has
    /// been told the truth, which is the point.
    ///
    /// This carries the header trait rather than the contextual line above it.
    /// The rotor should land a VoiceOver reader on the sheet's argument, and the
    /// line that changes with whatever they ran into is not it.
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

    private var description: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.loose) {
            VStack(alignment: .leading, spacing: Theme.Spacing.standard) {
                wordmark
                header
                boundary
            }

            PlusBenefits()
        }
    }

    private var purchaseControls: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.loose) {
            plans
            purchaseButton
            SubscriptionTerms(plan: plan)
        }
    }

    private var plans: some View {
        VStack(spacing: Theme.Spacing.close) {
            ForEach(SubscriptionPlan.allCases, id: \.self) { plan in
                planRow(plan)
            }
        }
    }

    /// The one thing on the sheet somebody is being asked to do.
    ///
    /// Ink rather than the brand accent, which is a legibility decision as much
    /// as a visual one: the system's white label over a full-strength accent is
    /// the contrast defect the audit already finds elsewhere in the app, and
    /// `Surface.ground` over `Ink.primary` is the pairing the whole palette is
    /// measured around.
    ///
    /// Only the fill departs. The width, the type and the height come from
    /// `primaryActionLabel()` and `Theme.Metrics.primaryActionInset`, which is
    /// the whole point of those two existing: a person meets Begin, Done and
    /// this button minutes apart, and the one that takes money must not be the
    /// one that stands six points taller.
    ///
    /// The dimming is drawn by hand for the same reason the fill is: a `plain`
    /// button draws exactly what its label says and nothing answers `disabled`
    /// on its behalf, where `.borderedProminent` used to. Without it the button
    /// looks live through a purchase and silently swallows the second tap.
    private var purchaseButton: some View {
        let isWaiting = store.isBusy || isHeld

        return Button {
            Task { await store.purchase(plan) }
        } label: {
            Text(callToAction)
                .primaryActionLabel()
                .foregroundStyle(Theme.Surface.ground)
                .padding(.vertical, Theme.Metrics.primaryActionInset)
                .background(Theme.Ink.primary, in: Capsule())
                .contentShape(Capsule())
                .opacity(isWaiting ? 0.4 : 1)
        }
        .buttonStyle(.plain)
        .disabled(isWaiting)
        .accessibilityLabel(purchaseAccessibilityLabel)
        .accessibilityIdentifier("paywall-purchase")
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
        .overlay {
            if isSelected {
                RoundedRectangle(cornerRadius: Theme.Radius.card)
                    .strokeBorder(
                        Theme.Accent.brand.opacity(Self.selectedRing),
                        lineWidth: 1
                    )
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel(for: candidate))
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
        .accessibilityIdentifier("paywall-plan-\(candidate.rawValue)")
    }

    /// The ring a chosen plan wears, at `FilterPill`'s strength — the app's one
    /// other accent ring around a chosen thing.
    ///
    /// A second carrier on top of the glass tint, because that wash is a
    /// difference somebody can miss in a bright room; the checkmark beside the
    /// title says it a third way.
    private static let selectedRing = 0.55

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
