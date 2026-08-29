import OndKit
import OndUI
import SwiftUI

/// The Coach tab, drawn at every tier: a tab that appears only on purchase
/// teaches nobody it exists. Chats live on this device only — the server
/// keeps no transcript. The gate reads `SubscriptionTier.assistant` against
/// this device's tier, which can lag the server's row after a purchase;
/// that window deliberately gets the chat and the server's copy, not a paywall.
struct CoachRootView: View {
    let assistant: any AssistantReading
    let chats: any ConversationStoring
    let catalogue: TechniqueListModel
    let sessions: any SessionRecording
    let foundations: FoundationsModel
    @Environment(SubscriptionStore.self) private var plus

    /// Read for the numbers on the check-ins door and written by the two tests
    /// behind it — the same practice model shared across the app, so a pause
    /// taken here is available before anybody navigates away. From the
    /// environment because the chat below it needs the same one for the coach's
    /// breath-hold card, and two routes to one model is one too many.
    @Environment(JourneyModel.self) private var journey

    @State private var conversations: ConversationListModel
    @State private var opened: Conversation?
    @State private var isShowingPaywall = false

    init(
        assistant: any AssistantReading,
        chats: any ConversationStoring,
        catalogue: TechniqueListModel,
        sessions: any SessionRecording,
        foundations: FoundationsModel
    ) {
        self.assistant = assistant
        self.chats = chats
        self.catalogue = catalogue
        self.sessions = sessions
        self.foundations = foundations
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
            // door, and a title stated twice is a title free to drift. The
            // display mode stays the default large: `.inline`, carried over
            // from `CoachChatView`, read as the collapsed form of a title
            // nobody had scrolled, next to the other tabs opening large.
            .navigationTitle("Coach")
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
        withCoachShortcuts(
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
        .coachGround()
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

    /// The basics and the check-ins pinned above whichever room is open — one
    /// shape, so the geometry cannot drift between tiers, and pinned rather than
    /// list rows, which acquire a `List`'s disclosure treatment. Intrinsic widths:
    /// a matched pair spanning the row would read as a segmented control. The
    /// check-ins sit here because only the coach reads either number back.
    private func withCoachShortcuts(_ room: some View) -> some View {
        VStack(spacing: Theme.Spacing.standard) {
            HStack(spacing: Theme.Spacing.close) {
                ShortcutLink(title: "The basics", systemImage: "book.closed") {
                    FoundationsView(model: foundations)
                }

                ShortcutLink(title: "Check-ins", systemImage: "waveform.path.ecg") {
                    CheckInsView(model: journey)
                }

                Spacer(minLength: 0)
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
            Label("Ask the coach", systemImage: CoachGlyph.symbol)
        } description: {
            Text(
                "Ask about your practice — which exercise fits how you slept, "
                    + "what your breath test means, where to go next."
            )
        } actions: {
            Button {
                opened = conversations.newConversation()
            } label: {
                // The same geometry as the offer's button below, and as every
                // other concluding action in the app. Left at the default it
                // drew a control two thirds the size of the one the locked room
                // shows in the same slot — the invitation reading as the lesser
                // of the two.
                Text("New conversation")
            }
            .buttonStyle(.inkAction)
        }
        // Centred in what the doors left rather than sitting directly under
        // them. `ContentUnavailableView` centres itself in the space it is
        // given, and inside a `VStack` that space is exactly its own height —
        // so without this the invitation reads as a third card in the stack.
        .frame(maxHeight: .infinity)
    }

    private var offer: some View {
        withCoachShortcuts(
            ContentUnavailableView {
                // The tab's own symbol — the offer is what is behind that door,
                // and a different glyph here would read as a different feature.
                Label("Your breathing coach", systemImage: CoachGlyph.symbol)
            } description: {
                Text(
                    "Ask where to start, why an exercise works, or what your "
                        + "comfortable pause is telling you — answered from your own "
                        + "practice, in your own words."
                )
            } actions: {
                Button {
                    isShowingPaywall = true
                } label: {
                    Text("See \(SubscriptionTier.assistant.title)")
                }
                .buttonStyle(.inkAction)
            }
            // Centred in what the doors left, on `emptyState`'s reasoning: the
            // two rooms sit in the same slot and must not be arranged
            // differently.
            .frame(maxHeight: .infinity)
        )
        .coachGround()
        .paywall(for: .coach, isPresented: $isShowingPaywall)
    }
}
