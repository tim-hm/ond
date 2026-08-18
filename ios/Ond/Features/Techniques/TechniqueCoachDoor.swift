import OndKit
import OndUI
import SwiftUI

/// The way from reading about an exercise to asking about it.
///
/// After the exercise's own explanation and evidence, where a follow-up question
/// belongs without interrupting the reading that may answer it first.
///
/// It is the whole of what replaced a streamed model paragraph that used to sit
/// above the figure explaining the physiology — a better trade than it looks.
/// Three paragraphs nobody asked for, on every visit, at a Bedrock call each,
/// become one line that spends nothing until somebody wants more, and what they
/// get then is a conversation they can ask a second question in.
///
/// Its own file rather than a private struct inside `TechniqueDetailView`,
/// because it is not only type: the door carries a conversation, which means a
/// store, a catalogue and a push — and the screen that owns the session, the
/// paywall and the dials has enough to hold.
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

    /// It pushes onto this stack rather than sending anybody to the Coach tab, so
    /// Back is the exercise they were reading and not wherever that tab was left.
    ///
    /// Drawn at every tier and opening on the offer below one, exactly as the
    /// Coach tab's own door does: a door somebody cannot open yet is still a
    /// door they can see. What it must not do is push the chat and let the
    /// server answer the refusal — that reads as a coach that ignored the
    /// question, and it is a paid completion's worth of screen for a sentence
    /// the paywall says better.
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
    /// message.
    ///
    /// Phrased as somebody would type it, because that is where it appears — in
    /// the trailing bubble, attributed to them. Naming the exercise rather than
    /// relying on context is what lets the transcript stand on its own when they
    /// come back to it in the Coach tab a week later.
    private static func opening(about technique: Technique) -> String {
        "Tell me about \(technique.name) — how does it work, and when should I use it?"
    }
}
