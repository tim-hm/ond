import OndKit
import OndUI
import SwiftUI

/// One subscription, at two prices, inside the system sheet chrome. The pitch
/// is `SubscriptionPitch`, shared with onboarding so one product cannot have
/// two hierarchies; this surface owns only dismissal, the requirement that
/// brought somebody here, and leaving once the entitlement arrives.
struct PaywallView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(SubscriptionStore.self) private var store

    /// What the person just ran into. The pitch remains one offer; the context
    /// decides which entitlement dismisses this particular sheet.
    private let context: PaywallContext

    /// Yearly by default, as in the reference and because it is the lower-cost
    /// cadence over a year. Either tile remains one tap away.
    @State private var plan: SubscriptionPlan = .yearly

    init(_ context: PaywallContext = .general) {
        self.context = context
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                SubscriptionPitch(
                    plan: $plan,
                    continuesWhenUnavailable: false
                ) {
                    Task { await store.purchase(plan) }
                }
                .padding(.horizontal, Theme.Spacing.page)
                .padding(.top, Theme.Spacing.close)
                .padding(.bottom, Theme.Spacing.loose)
            }
            .scrollBounceBehavior(.basedOnSize)
            .background(Theme.Surface.ground)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Not now") { dismiss() }
                }
            }
            .sensoryFeedback(.success, trigger: isHeld)
            .onChange(of: store.tier) { _, tier in
                if tier >= context.requires {
                    dismiss()
                }
            }
            .task { await store.loadProducts() }
        }
    }

    /// Whether this person already holds what the presenting feature requires.
    private var isHeld: Bool {
        store.tier >= context.requires
    }
}
