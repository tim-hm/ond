import OndKit
import OndUI
import SwiftUI

/// Why an exercise works, and the way to ask for more — what the detail screen
/// opens on, above the figure. How you *do* it lives below the figure, in
/// `TechniquePractice`, as a caption on the drawing of it.
///
/// Two things in that order, and no third. A streamed model paragraph used to
/// sit between the summary and the figure explaining the physiology, and it is
/// gone: it cost a Bedrock call on every visit to put three paragraphs between a
/// person and the button they came for, and the coach door below answers the same
/// question better — on demand, in a conversation that can be asked a second
/// question.
///
/// Its own file rather than a private struct inside `TechniqueDetailView`,
/// because it stopped being only type: the coach door carries a conversation,
/// which means a store, a catalogue and a push — and the screen that owns the
/// session, the paywall and the dials has enough to hold.
struct TechniqueHeader: View {
    /// The curated technique, deliberately not the dialled copy: nothing this
    /// header reads is a thing a dial moves, and the stable input is what lets
    /// SwiftUI skip re-rendering it on every drag while the dials sheet is up.
    let technique: Technique

    let assistant: any AssistantReading

    /// The three the coach door needs behind it: the conversation store to write
    /// into, the catalogue an offered exercise resolves against, and the recorder
    /// a session started from that offer reports to.
    let chats: any ConversationStoring
    let catalogue: TechniqueListModel
    let sessions: any SessionRecording

    /// The conversation this screen opened, if any. A fresh `Conversation` is
    /// in-memory only — the store refuses to persist an empty one — so a person
    /// who opens the coach and comes straight back leaves nothing behind.
    @State private var asking: Conversation?

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.standard) {
            // At the weight of something meant to be read: primary ink, and its
            // paragraphs kept apart.
            Text(technique.opening)
                .font(.body)
                .foregroundStyle(Theme.Ink.primary)

            if technique.origin == .catalogue {
                askButton
            }
        }
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
    }

    /// The way from reading about an exercise to asking about it.
    ///
    /// The whole of what replaced the streamed explanation, and a better trade
    /// than it looks: three paragraphs nobody asked for, on every visit, at a model
    /// call each, become one line that spends nothing until somebody wants more —
    /// and what they get then is a conversation they can ask a second question in.
    ///
    /// It pushes onto this stack rather than sending anybody to the Coach tab, so
    /// Back is the exercise they were reading and not wherever that tab was left.
    ///
    /// Ungated. The server is what decides whether a model answers — a tier that
    /// does not buy one gets the rule-based reply, and the chat screen already says
    /// so in its own words — so a gate here would be a second opinion on that,
    /// free to disagree with it.
    ///
    /// Only for a catalogue exercise, which is the same rule the explanation
    /// keeps: the coach is briefed on the seeded techniques, and it has nothing
    /// to say about one somebody wrote this morning.
    private var askButton: some View {
        Button {
            asking = Conversation()
        } label: {
            Label("Ask the coach about this", systemImage: "signpost.right")
                .font(.subheadline.weight(.semibold))
        }
        // Plain and tinted rather than bordered: Begin is the button on this
        // screen, and a second filled control in the reading half would argue
        // with it.
        .buttonStyle(.plain)
        .foregroundStyle(Theme.Accent.brand)
        .frame(minHeight: 44)
        .contentShape(.rect)
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
