import OndKit
import OndUI
import SwiftUI

/// One subscription, at two prices, and the links App Review will not approve a
/// paywall without.
///
/// The copy leads with what stays free, which is the honest framing and also the
/// product's: everything that runs on this device — every exercise and protocol,
/// custom exercises, the player, your journey, the watch app itself — is not for
/// sale and never was. What önd+ sells is the handful of things with a cost per
/// use behind them: the coach asking a language model on this person's behalf,
/// the leaderboards the server folds, the health trends the coach reasons from,
/// and the wrist working together with the phone.
///
/// One card rather than the two-tier ladder this replaces. A ladder makes
/// somebody choose between products before they have decided they want either;
/// the only choice left here is how often they are billed, which is a choice
/// with an obvious answer and a badge on it.
struct PaywallView: View {
    @Environment(\.dismiss) private var dismiss

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
                    offer
                    free
                }
                .padding(Theme.Spacing.standard)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(Theme.Surface.ground)
            .safeAreaInset(edge: .bottom) { legalBar }
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
        VStack(alignment: .leading, spacing: Theme.Spacing.close) {
            Text(context.headline)
                .font(.title2.weight(.semibold))
                .foregroundStyle(Theme.Ink.primary)

            Text(
                """
                önd works without it. önd+ opens the parts that need a server \
                behind them — your coach, the boards, what your body is doing \
                between sessions, and your watch working with your phone.
                """
            )
            .font(.body)
            .foregroundStyle(Theme.Ink.secondary)
        }
    }

    private var offer: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.standard) {
            VStack(alignment: .leading, spacing: Theme.Spacing.close) {
                ForEach(Self.benefits, id: \.self) { benefit in
                    Label(benefit, systemImage: "checkmark")
                        .font(.subheadline)
                        .foregroundStyle(Theme.Ink.secondary)
                        .labelStyle(.titleAndIcon)
                }
            }

            VStack(spacing: Theme.Spacing.tight) {
                ForEach(SubscriptionPlan.allCases, id: \.self) { plan in
                    planRow(plan)
                }
            }

            Button {
                Task { await store.purchase(plan) }
            } label: {
                Text(callToAction).primaryActionLabel()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .tint(Theme.Accent.brand)
            .disabled(store.isBusy || isHeld)
        }
        .padding(Theme.Spacing.standard)
        .background(Theme.Surface.raised, in: RoundedRectangle(cornerRadius: Theme.Radius.card))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Radius.card)
                .strokeBorder(Theme.Accent.brand, lineWidth: 2)
        )
    }

    /// One cadence, as a row somebody chooses between rather than a segmented
    /// control: the yearly row carries a saving badge, and a segment has nowhere
    /// to put one.
    private func planRow(_ candidate: SubscriptionPlan) -> some View {
        let isSelected = candidate == plan

        return Button {
            plan = candidate
        } label: {
            HStack(alignment: .firstTextBaseline, spacing: Theme.Spacing.close) {
                Text(title(of: candidate))
                    .font(.subheadline.weight(isSelected ? .semibold : .regular))
                    .foregroundStyle(Theme.Ink.primary)

                if candidate == .yearly, let saving = store.annualSaving {
                    Text("Save \(saving)%")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Theme.Accent.brand)
                }

                Spacer(minLength: Theme.Spacing.close)

                Text(price(of: candidate))
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(Theme.Ink.secondary)
            }
            .padding(Theme.Spacing.close)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(
            RoundedRectangle(cornerRadius: Theme.Radius.card)
                .strokeBorder(
                    isSelected ? Theme.Accent.brand : Theme.Surface.line,
                    lineWidth: isSelected ? 2 : 1
                )
        )
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }

    /// What önd+ opens, in the person's terms — four lines, one per thing that
    /// costs something to serve.
    private static let benefits = [
        "Your coach, answering from your own practice",
        "The leaderboards, globally and in your age band",
        "What your resting rate and HRV are doing",
        "Sessions sent to your watch, and its heart rate here",
    ]

    /// "Try 7 days free" only where there is a trial on *this* plan that this
    /// person can actually take.
    ///
    /// Read from the selected plan rather than from whichever product happens
    /// to carry an offer: eligibility is per subscription group, but the offer
    /// itself is per product and App Store Connect is free to put one on only
    /// the monthly. A button promising a trial the purchase then does not
    /// honour is a 3.1.2 violation as well as a lie.
    private var trialDays: Int? {
        store.product(for: plan)?.introductoryOffer.flatMap { $0.isEligible ? $0.trialDays : nil }
    }

    /// Whether this person already holds what they came here for — the one
    /// question this screen asks about the tier, read against the context's own
    /// lever rather than against a rung typed in here.
    private var isHeld: Bool {
        store.tier >= context.requires
    }

    private var callToAction: String {
        guard !isHeld else { return "Your plan" }
        guard let days = trialDays else { return "Subscribe" }

        return "Try \(days) days free"
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

        return switch plan {
        case .monthly: "\(product.displayPrice) / month"
        case .yearly: "\(product.displayPrice) / year"
        }
    }

    private var free: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.close) {
            Text("Always free")
                .font(.headline)
                .foregroundStyle(Theme.Ink.primary)

            Text(
                """
                Every exercise and every protocol, the exercises you build \
                yourself, the guided player with haptics and sound, your whole \
                journey, and the Apple Watch app.
                """
            )
            .font(.subheadline)
            .foregroundStyle(Theme.Ink.secondary)
        }
    }

    /// Pinned to the bottom, because Restore Purchases, the renewal terms and
    /// the two documents have to be reachable without reading to the end of the
    /// page.
    private var legalBar: some View {
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

            HStack(spacing: Theme.Spacing.standard) {
                Button("Restore Purchases") {
                    Task { await store.restore() }
                }
                .disabled(store.isBusy)

                Link("Privacy", destination: LegalLinks.privacyPolicy)
                Link("Terms", destination: LegalLinks.termsOfUse)
            }
            .font(.footnote)
            .tint(Theme.Accent.brand)
        }
        .padding(Theme.Spacing.standard)
        .background(.bar)
    }

    /// What App Review's guideline 3.1.2 requires beside an offer: the length of
    /// the trial, the price that follows it, how often it recurs, and that it
    /// can be cancelled. Composed from the App Store's own price so it is right
    /// in every storefront, and it drops the trial clause where there is no
    /// trial on offer rather than promising one this person cannot take.
    private var renewalTerms: String {
        let period = plan == .monthly ? "month" : "year"
        let price = store.product(for: plan)?.displayPrice

        guard let price else {
            return "Renews automatically until cancelled. Cancel any time in Settings."
        }

        guard let days = trialDays else {
            return "\(price) per \(period), renewing automatically until cancelled. "
                + "Cancel any time in Settings."
        }

        return "\(days) days free, then \(price) per \(period), renewing automatically "
            + "until cancelled. Cancel any time in Settings."
    }
}
