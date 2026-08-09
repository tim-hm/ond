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
/// Behind the door, the room is the conversation list: every chat this person
/// has had with the coach, most recent first, with a new one a toolbar tap
/// away. The chats themselves live on this device only — the server keeps no
/// transcript — so the list is the whole of what exists.
///
/// Either room opens with the basics — belly or chest, nose or mouth. They are
/// the coach's material rather than the journey's: education, not progress.
/// Above the offer they are the taster of what coaching is, and they keep a
/// closed room from being an empty one.
///
/// The offer is a screen rather than a line because it has a whole tab to fill,
/// and `ContentUnavailableView` is the shape the rest of the app already uses
/// where a screen has to explain itself instead of showing content. **It draws
/// for nobody today**: the gate reads `SubscriptionTier.assistant`, which is
/// `.free` while the featureset settles, so every visitor gets the chat. Both
/// branches stay because that constant is one line, and a room deleted for
/// being unreachable is a room to rebuild rather than reopen.
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
    let chats: any ConversationStoring
    let catalogue: TechniqueListModel
    let sessions: any SessionRecording
    let foundations: FoundationsModel
    /// Read for the numbers on the check-ins door and written by the two tests
    /// behind it — the same model the Journey tab folds, so a pause taken here
    /// is on that tab before anybody navigates to it.
    let journey: JourneyModel

    @Environment(SubscriptionStore.self) private var plus

    @State private var conversations: ConversationListModel
    @State private var opened: Conversation?
    @State private var isShowingPaywall = false

    init(
        assistant: any AssistantReading,
        chats: any ConversationStoring,
        catalogue: TechniqueListModel,
        sessions: any SessionRecording,
        foundations: FoundationsModel,
        journey: JourneyModel
    ) {
        self.assistant = assistant
        self.chats = chats
        self.catalogue = catalogue
        self.sessions = sessions
        self.foundations = foundations
        self.journey = journey
        _conversations = State(wrappedValue: ConversationListModel(store: chats))
    }

    var body: some View {
        NavigationStack {
            Group {
                if plus.tier >= .assistant {
                    list
                } else {
                    offer
                }
            }
            // On the stack rather than on each branch: both rooms are the same
            // door, and a title stated twice is a title free to drift.
            .navigationTitle("Coach")
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(item: $opened) { conversation in
                CoachChatView(
                    conversation: conversation,
                    chats: chats,
                    assistant: assistant,
                    catalogue: catalogue,
                    sessions: sessions
                )
            }
        }
    }

    private var list: some View {
        withBasics(
            Group {
                if conversations.conversations.isEmpty {
                    emptyState
                } else {
                    List {
                        ForEach(conversations.conversations) { conversation in
                            row(for: conversation)
                        }
                        .onDelete { offsets in
                            Task { await conversations.delete(at: offsets) }
                        }
                        .listRowBackground(Theme.Surface.raised)
                    }
                    .scrollContentBackground(.hidden)
                }
            }
        )
        .paletteGround()
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                newChatButton
            }
        }
        // Keyed on the pushed chat, so popping back re-reads the store — which
        // is exactly when a title or a recency can have changed. The two loads
        // run concurrently because they share nothing, one of them may go to
        // the network, and this room is now every visitor's rather than a
        // subscriber's — so the serial version's latency is paid by everybody.
        .task(id: opened?.id) {
            guard opened == nil else { return }
            async let conversationsLoaded: Void = conversations.load()
            async let catalogueLoaded: Void = catalogue.loadIfNeeded()
            _ = await (conversationsLoaded, catalogueLoaded)
        }
    }

    private func row(for conversation: Conversation) -> some View {
        Button {
            opened = conversation
        } label: {
            VStack(alignment: .leading, spacing: Theme.Spacing.tight) {
                Text(conversation.title ?? "New conversation")
                    .font(.body)
                    .foregroundStyle(Theme.Ink.primary)
                    .lineLimit(1)
                Text(conversation.updatedAt, format: .relative(presentation: .named))
                    .font(.footnote)
                    .foregroundStyle(Theme.Ink.tertiary)
            }
        }
    }

    private var newChatButton: some View {
        Button {
            opened = conversations.newConversation()
        } label: {
            Image(systemName: "square.and.pencil")
        }
        .accessibilityLabel("New conversation")
    }

    /// The way into the basics, in both rooms and at every tier.
    private var basicsCard: some View {
        DoorCard(
            title: "The basics",
            caption: "Belly or chest, nose or mouth, sitting or lying down."
        ) {
            FoundationsView(model: foundations)
        }
    }

    /// The way into the two measurements, beside the basics and at every tier.
    ///
    /// Here rather than on Journey because a check-in is the coach's material:
    /// the journey is what you did, and these are what your breathing is doing
    /// when you are not doing anything about it. The coach is also the only
    /// thing in the app that reads either number back — both ride in its
    /// briefing and in its rule-based fallback — so the tab that can explain
    /// them is the tab that offers them.
    private var checkInsCard: some View {
        DoorCard(
            title: "Check-ins",
            caption: "Your comfortable pause and your resting rate."
        ) {
            CheckInsView(model: journey)
        }
    }

    /// The basics and the check-ins pinned above whichever room is open — the
    /// chat list, the empty invitation, or the offer. One shape rather than a
    /// per-room placement, so the cards' geometry cannot drift between tiers;
    /// pinned rather than rows of the list, because a `List`-hosted
    /// `NavigationLink` takes the system disclosure chevron on top of the card's
    /// own.
    private func withBasics(_ room: some View) -> some View {
        VStack(spacing: Theme.Spacing.standard) {
            VStack(spacing: Theme.Spacing.standard) {
                basicsCard
                checkInsCard
            }
            .padding(.horizontal, Theme.Spacing.standard)
            .padding(.top, Theme.Spacing.standard)
            room
        }
    }

    /// What no conversations says instead of blank space: the same invitation
    /// the chat screen used to open with, with the way in as its action.
    private var emptyState: some View {
        ContentUnavailableView {
            Label("Ask the coach", systemImage: "signpost.right")
        } description: {
            Text(
                "Ask about your practice — which exercise fits how you slept, "
                    + "what your breath test means, where to go next."
            )
        } actions: {
            Button("New conversation") {
                opened = conversations.newConversation()
            }
            .buttonStyle(.borderedProminent)
        }
    }

    private var offer: some View {
        withBasics(
            ContentUnavailableView {
                // The tab's own symbol — the offer is what is behind that door,
                // and a different glyph here would read as a different feature.
                Label("Your breathing coach", systemImage: "signpost.right")
            } description: {
                Text(
                    "Ask where to start, why an exercise works, or what your "
                        + "comfortable pause is telling you — answered from your own "
                        + "practice, in your own words."
                )
            } actions: {
                Button("See \(SubscriptionTier.assistant.brandedTitle)") {
                    isShowingPaywall = true
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            }
        )
        .paletteGround()
        .paywall(highlighting: .assistant, isPresented: $isShowingPaywall)
    }
}
