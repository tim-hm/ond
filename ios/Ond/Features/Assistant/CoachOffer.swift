import OndKit
import OndUI
import SwiftUI

/// The Coach tab below the tier: the room, stated rather than sealed. One
/// untinted card says what the coach is and where the boundary runs, and the
/// composer underneath is the real one, disabled — somebody deciding whether
/// to pay should see what they would be typing into, not a locked door.
struct CoachOffer: View {
    @State private var draft = ""
    @State private var isShowingPaywall = false

    /// The composer owns a focus binding it can never take: the field below is
    /// disabled, so this stays false for the life of the screen.
    @FocusState private var isComposing: Bool

    var body: some View {
        VStack(spacing: 0) {
            card
                .padding(.horizontal, Theme.Spacing.standard)
                .frame(maxHeight: .infinity, alignment: .top)

            CoachComposer(
                draft: $draft,
                isReplying: true,
                lastReplySource: nil,
                isComposing: $isComposing,
                send: {}
            )
            .disabled(true)
        }
        .paywall(for: .coach, isPresented: $isShowingPaywall)
    }

    private var card: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.close) {
            Text("Your breathing coach")
                .font(.headline)
                .foregroundStyle(Theme.Ink.primary)
                .accessibilityAddTraits(.isHeader)

            Text(
                "önd+ is only the connected layer. If you never want it, "
                    + "the app is complete without it."
            )
            .font(.callout)
            .foregroundStyle(Theme.Ink.secondary)

            Button("See \(SubscriptionTier.assistant.title)") {
                isShowingPaywall = true
            }
            .buttonStyle(.plain)
            .font(.subheadline)
            .foregroundStyle(Theme.Accent.brandText)
            .padding(.top, Theme.Spacing.tight)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Theme.Spacing.standard)
        .glassCard()
    }
}
