import OndKit
import OndUI
import SwiftUI

/// The Coach tab, which is one door with two rooms behind it.
///
/// The tab is drawn at every tier rather than only for subscribers. A tab that
/// appears on purchase teaches nobody it exists, and the thing this app sells
/// went unfound twice already for exactly that reason — once behind a swipe-up
/// drawer, once behind a strip that only rendered under a fallback answer. A
/// door somebody cannot open yet is still a door they can see.
///
/// The offer is a screen rather than a line because it has a whole tab to fill,
/// and `ContentUnavailableView` is the shape the rest of the app already uses
/// where a screen has to explain itself instead of showing content.
///
/// The gate reads *this device's* tier, which is `StoreKit`'s answer, while the
/// server spends against its own row — so the two disagree for as long as a
/// receipt takes to sync, and a purchase made against the local `.storekit`
/// configuration never syncs at all. Somebody in that window gets the chat and
/// a reply flagged `SUBSCRIPTION_REQUIRED`, and that is deliberately not
/// treated as grounds to shut the door on them: they have paid, and a paywall
/// raised at a paying subscriber over a sync delay is a worse failure than the
/// one this gate is for. The server's copy carries them instead — it names the
/// subscription and points at the restore.
struct CoachRootView: View {
    let assistant: any AssistantReading

    @Environment(SubscriptionStore.self) private var plus

    @State private var isShowingPaywall = false

    var body: some View {
        NavigationStack {
            Group {
                if plus.tier >= .coach {
                    CoachChatView(assistant: assistant)
                } else {
                    offer
                }
            }
            // On the stack rather than on each branch: both rooms are the same
            // door, and a title stated twice is a title free to drift.
            .navigationTitle("Coach")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private var offer: some View {
        ContentUnavailableView {
            // The tab's own symbol — the offer is what is behind that door, and
            // a different glyph here would read as a different feature.
            Label("Your breathing coach", systemImage: "bubble.left.and.text.bubble.right")
        } description: {
            Text(
                "Ask where to start, why an exercise works, or what your "
                    + "comfortable pause is telling you — answered from your own "
                    + "practice, in your own words."
            )
        } actions: {
            Button("See \(SubscriptionTier.coach.brandedTitle)") {
                isShowingPaywall = true
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
        .paletteGround()
        .paywall(highlighting: .coach, isPresented: $isShowingPaywall)
    }
}
