import OndKit
import SwiftUI

/// The shared önd+ pitch as it appears during first-run onboarding. The flow
/// keeps Back, progress and Not now in native chrome; the content is the same
/// `SubscriptionPitch` the paywall sheet draws, both cadences included, so
/// first run no longer introduces a second one-plan version of the product.
struct TrialStepView: View {
    /// The offline way forward. A missing App Store product must not turn first
    /// launch into a dead end.
    let onContinue: () -> Void

    @Environment(SubscriptionStore.self) private var store

    /// Yearly opens selected, matching the reference. Someone who wants the
    /// smaller commitment can choose Monthly in the adjacent tile.
    @State private var plan: SubscriptionPlan = .yearly

    var body: some View {
        SubscriptionPitch(
            plan: $plan,
            continuesWhenUnavailable: true
        ) {
            if store.offer(for: plan) == .unavailable {
                onContinue()
            } else {
                Task { await store.purchase(plan) }
            }
        }
    }
}
