import OndKit
import OndUI
import SwiftUI

/// The way from reading about an exercise to asking about it. It replaced a
/// streamed model paragraph above the figure: three paragraphs nobody asked
/// for, at a Bedrock call per visit, became one line that spends nothing
/// until somebody wants more. Its own file because the door carries a
/// conversation — a store, a catalogue and a push of its own.
struct TechniqueCoachDoor: View {
    /// The curated technique, deliberately not the dialled copy: nothing here
    /// reads a value a dial moves, and the stable input is what lets SwiftUI skip
    /// re-rendering while the dials sheet is up.
    let technique: Technique

    let assistant: any AssistantReading

    /// The three the door needs behind it: the conversation store to write into,
    /// the catalogue an offered exercise resolves against, and the recorder a
    /// session started from that offer reports to.
    let chats: any ConversationStoring
    let catalogue: TechniqueListModel
    let sessions: any SessionRecording

    @Environment(SubscriptionStore.self) private var plus

    /// The conversation this screen opened, if any. A fresh `Conversation` is
    /// in-memory only — the store refuses to persist an empty one — so a person
    /// who opens the coach and comes straight back leaves nothing behind.
    @State private var asking: Conversation?

    @State private var isShowingPaywall = false

    var body: some View {
        askButton
            .navigationDestination(item: $asking) { conversation in
                CoachChatView(
                    conversation: conversation,
                    chats: chats,
                    assistant: assistant,
                    catalogue: catalogue,
                    sessions: sessions,
                    opening: Self.opening(about: technique)
                )
            }
            .paywall(for: .coach, isPresented: $isShowingPaywall)
    }

    /// Pushes onto this stack, so Back is the exercise they were reading.
    /// Drawn at every tier and opening the offer below one — a door somebody
    /// cannot open yet is still a door they can see. It must not push the chat
    /// and let the server answer the refusal: that reads as a coach ignoring
    /// the question, at a paid completion's cost.
    private var askButton: some View {
        Button {
            if plus.tier >= .assistant {
                asking = Conversation()
            } else {
                isShowingPaywall = true
            }
        } label: {
            Label("Ask the coach", systemImage: CoachGlyph.symbol)
                .font(.subheadline.weight(.semibold))
        }
        .buttonStyle(.glass)
        .controlSize(.large)
        .tint(Theme.Accent.brand)
        .accessibilityLabel("Ask the coach about \(technique.name)")
    }

    /// The question the conversation opens on, sent as the person's own first
    /// message and phrased as they would type it — it appears in the trailing
    /// bubble, attributed to them. It names the exercise so the transcript
    /// stands alone when reread in the Coach tab later.
    private static func opening(about technique: Technique) -> String {
        "Tell me about \(technique.name) — how does it work, and when should I use it?"
    }
}
