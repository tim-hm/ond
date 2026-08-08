import AuthenticationServices
import OndKit
import OndUI
import SwiftUI

/// The two subscriptions, what each opens, and the links App Review will not
/// approve a paywall without.
///
/// The copy leads with what stays free, which is the honest framing and also the
/// product's: the player, the journey, the leaderboards and the basics are not
/// for sale, and neither are the two techniques the app opens with. Plus sells
/// the rest of the catalogue. Coach sells the one feature that costs money to
/// run — the assistant asking a language model on this person's behalf.
///
/// Both tiers on one screen rather than two sheets. They are a ladder, not
/// alternatives, and somebody deciding between them should be able to see the
/// difference without going back.
struct PaywallView: View {
    @Environment(\.dismiss) private var dismiss

    /// From the environment, like `SessionSettings`: `OndApp` owns the one
    /// instance, and the surfaces that offer a subscription are nowhere near it.
    @Environment(SubscriptionStore.self) private var store

    /// Read here for one reason: a purchase has to be filed against an identity
    /// its owner can recover, so buying signs in first. Settings is where the
    /// state is otherwise managed, and nothing on this screen shows it.
    @Environment(AccountModel.self) private var account

    /// Which tier the sheet opens on. The surface that presented it knows why
    /// somebody is here — a locked technique means Plus, an assistant answer
    /// from the rules means Coach — and leading with the one that answers their
    /// question is the difference between an offer and a price list.
    let highlighted: SubscriptionTier

    init(highlighting tier: SubscriptionTier = .plus) {
        highlighted = tier
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Spacing.loose) {
                    header

                    ForEach(SubscriptionTier.purchasable, id: \.self) { tier in
                        offer(tier)
                    }

                    free
                }
                .padding(Theme.Spacing.standard)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(Theme.Surface.ground)
            .safeAreaInset(edge: .bottom) { legalBar }
            .navigationTitle("Subscriptions")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
            // Dismisses itself once the tier somebody came for is theirs, rather
            // than leaving them looking at a paywall for something they now own.
            // Compared, not equated: buying Coach answers a Plus prompt too.
            .onChange(of: store.tier) { _, tier in
                if tier >= highlighted {
                    dismiss()
                }
            }
            .task { await store.loadProducts() }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.close) {
            Text(headline)
                .font(.title2.weight(.semibold))
                .foregroundStyle(Theme.Ink.primary)

            Text(
                """
                önd works without either of these. They open up the rest of \
                the catalogue, and an assistant that reads what you told us and \
                answers in your own words.
                """
            )
            .font(.body)
            .foregroundStyle(Theme.Ink.secondary)
        }
    }

    /// Names what they came for rather than what is for sale.
    private var headline: String {
        switch highlighted {
        case .coach: "An assistant that knows your practice"
        case .plus, .free: "The whole catalogue"
        }
    }

    private func offer(_ tier: SubscriptionTier) -> some View {
        let isHeld = store.tier >= tier
        let isHighlighted = tier == highlighted

        return VStack(alignment: .leading, spacing: Theme.Spacing.standard) {
            HStack(alignment: .firstTextBaseline) {
                Text(tier.title)
                    .font(.headline)
                    .foregroundStyle(Theme.Ink.primary)
                Spacer(minLength: Theme.Spacing.close)
                Text(price(for: tier))
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(Theme.Ink.secondary)
            }

            VStack(alignment: .leading, spacing: Theme.Spacing.close) {
                ForEach(tier.benefits, id: \.self) { benefit in
                    Label(benefit, systemImage: "checkmark")
                        .font(.subheadline)
                        .foregroundStyle(Theme.Ink.secondary)
                        .labelStyle(.titleAndIcon)
                }
            }

            Button {
                Task { await buy(tier) }
            } label: {
                Text(isHeld ? "Your plan" : callToAction(for: tier))
                    .font(.headline)
                    .frame(maxWidth: .infinity)
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
                .strokeBorder(
                    isHighlighted ? Theme.Accent.brand : Theme.Surface.line,
                    lineWidth: isHighlighted ? 2 : 1
                )
        )
    }

    /// Buys `tier`, signing in with Apple first where this install never has.
    ///
    /// **After the tap, never before it.** A sign-in in front of the prices
    /// reads as a wall and costs the sale; the same sheet after somebody has
    /// chosen a plan reads as part of buying — and `StoreKit` is about to raise
    /// an Apple sheet of its own, so the two are consecutive rather than
    /// separated by anything else.
    ///
    /// The reason is durability rather than security, which is also the honest
    /// framing for the person: an entitlement is filed against the önd identity,
    /// so an anonymous buyer whose Keychain does not follow them to a new phone
    /// has nothing for Restore Purchases to find. `SubmitAppStoreTransaction`
    /// refuses an identity that has never signed in, and this is what stops
    /// somebody meeting that refusal after they have already paid.
    ///
    /// Nothing here gates the free tier, which stays entirely anonymous.
    ///
    /// A cancelled sheet buys nothing and says nothing: backing out is a
    /// decision, and `AccountSection.report` takes the same view of it.
    private func buy(_ tier: SubscriptionTier) async {
        if account.state == .localOnly {
            do {
                let identityToken = try await AppleIdentityRequest().freshIdentityToken()
                await account.signIn(identityToken: identityToken)
            } catch {
                if (error as? ASAuthorizationError)?.code != .canceled {
                    account.reportSignInFailure(error.localizedDescription)
                }
                return
            }

            // The sign-in itself can fail on the server — a device already bound
            // to another Apple ID is the reachable case — and buying now would
            // file the purchase against an identity that still cannot hold it.
            guard account.state == .signedIn, account.failure == nil else { return }
        }

        await store.purchase(tier)
    }

    /// Says "Upgrade" rather than "Get" when somebody already pays for the tier
    /// below. Both products live in one subscription group, so this genuinely is
    /// a change of plan — Apple prorates it and there is never a second charge.
    private func callToAction(for tier: SubscriptionTier) -> String {
        store.tier > .free ? "Upgrade" : "Get \(tier.title)"
    }

    /// The price comes from the App Store or not at all: it varies by
    /// storefront, and a hardcoded amount would be wrong in most countries and
    /// illegal in a few. A missing one reads as a blank rather than a guess —
    /// somebody with no signal can still see what each tier is and buy it when
    /// the sheet loads.
    private func price(for tier: SubscriptionTier) -> String {
        guard let product = store.products.first(where: { $0.tier == tier }) else {
            return " "
        }

        return "\(product.displayPrice) a month"
    }

    private var free: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.close) {
            Text("Always free")
                .font(.headline)
                .foregroundStyle(Theme.Ink.primary)

            Text(
                """
                Box breathing and the physiological sigh, the guided player with \
                haptics and sound, your whole journey, the leaderboards, the \
                basics, and the Apple Watch app.
                """
            )
            .font(.subheadline)
            .foregroundStyle(Theme.Ink.secondary)
        }
    }

    /// Pinned to the bottom, because Restore Purchases and the two documents
    /// have to be reachable without reading to the end of the page.
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
                Text("These aren't on sale right now. Nothing was charged.")
                    .font(.footnote)
                    .foregroundStyle(Theme.Ink.secondary)
                    .multilineTextAlignment(.center)
            }

            // Only for somebody who would meet the sheet. It says what signing
            // in is *for* — a subscription that survives a new phone, which is
            // what makes Restore Purchases above it mean anything — rather than
            // anything about protecting an account, and it says nothing about
            // the free tier, which stays entirely anonymous.
            if account.state == .localOnly {
                Text("Sign in so your subscription follows you to a new phone.")
                    .font(.caption)
                    .foregroundStyle(Theme.Ink.tertiary)
                    .multilineTextAlignment(.center)
            }

            Text("Renews monthly. Cancel any time in Settings.")
                .font(.caption)
                .foregroundStyle(Theme.Ink.tertiary)

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
}

private extension SubscriptionTier {
    /// What each tier opens, in the person's terms. Coach lists what it adds
    /// rather than repeating Plus, with one line saying it contains it — a
    /// second copy of the same three bullets makes the ladder harder to read,
    /// not easier.
    var benefits: [String] {
        switch self {
        case .free:
            []
        case .plus:
            [
                "Every exercise in the catalogue",
                "Sleep, focus, and energy protocols",
                "The Wim Hof-style rounds",
            ]
        case .coach:
            [
                "Everything in Plus",
                "Where to start, written for you",
                "Why any exercise works, at your level",
            ]
        }
    }
}
