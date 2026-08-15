import OndKit
import OndUI
import SwiftUI

/// One conversation with the coach, drawn as a messenger thread: the person's
/// messages in right-aligned bubbles, the coach's in left-aligned ones, and a
/// coach reply that ends on an exercise offer growing a card the person can
/// start the session from.
///
/// Reached two ways. From `CoachRootView`, which is where the tier gate and the
/// conversation list live, on an empty conversation or one being resumed; and
/// from an exercise's own screen, which pushes it with `opening` set so the
/// conversation starts on the question that screen was about. Either way the
/// turns persist through the store it is handed, so a conversation begun from an
/// exercise is in the Coach tab's list like any other.
///
/// Phone-only by design. The watch deliberately has no chat surface: text
/// entry is hostile on the wrist, and dictating a coaching question into a
/// watch is not a conversation anybody asked for.
struct CoachChatView: View {
    let catalogue: TechniqueListModel
    let sessions: any SessionRecording

    @Environment(SubscriptionStore.self) private var plus
    @Environment(SessionSettings.self) private var settings

    /// The check-ins' model, so a breath-hold the coach offered is taken here
    /// and lands in Check-ins like one taken from its own door. From the
    /// environment rather than threaded: this screen sits four views below the
    /// screen that owns it on one of its two routes in, and the three screens
    /// between do not otherwise know it exists.
    @Environment(JourneyModel.self) private var journey

    /// The person's own exercises, which a save-this-pattern card writes into.
    /// From the environment for the same reason the journey is.
    @Environment(UserTechniqueModel.self) private var own
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var model: CoachChatModel
    @State private var draft = ""
    @State private var started: PhoneSessionLaunch?
    /// Whether the coach offered an exercise this tier does not open. Which one
    /// is not kept — there is one subscription to sell either way.
    @State private var isShowingPaywall = false
    @State private var isTakingBoltTest = false

    /// The question this screen scrolled to the top, and therefore the start of
    /// the exchange being watched. Nil until the first send of the visit, which
    /// is what leaves a resumed conversation opening exactly as it always did.
    @State private var pinned: UUID?

    /// Whether the composer holds the keyboard — which is both what raises the
    /// dismiss button and what that button acts on.
    @FocusState private var isComposing: Bool

    /// The question to ask on arrival, for a conversation opened *about*
    /// something — an exercise's coach door names the exercise. Sent as the
    /// person's own first turn rather than typed into the composer for them: the
    /// button they pressed said what it would ask, and leaving them a filled field
    /// and a send button to press is a second tap that changes nothing.
    ///
    /// Nil is a conversation somebody opened to say whatever they like, which is
    /// every conversation the Coach tab makes.
    private let opening: String?

    /// The assistant and the store arrive from the composition root, through
    /// `CoachRootView` or through the exercise screen that pushed this.
    init(
        conversation: Conversation,
        chats: any ConversationStoring,
        assistant: any AssistantReading,
        catalogue: TechniqueListModel,
        sessions: any SessionRecording,
        opening: String? = nil
    ) {
        self.catalogue = catalogue
        self.sessions = sessions
        self.opening = opening
        _model = State(wrappedValue: CoachChatModel(
            conversation: conversation,
            store: chats,
            assistant: assistant
        ))
    }

    var body: some View {
        // The composer is a safe-area inset rather than the second half of a
        // `VStack`, so the transcript keeps the whole screen and scrolls under
        // both it and the tab bar. Stacked, the two chrome bars ate the bottom
        // of every conversation and the newest turn was the one they hid.
        conversation
            .safeAreaInset(edge: .bottom) {
                CoachComposer(
                    draft: $draft,
                    isReplying: model.isReplying,
                    lastReplySource: model.lastReplySource,
                    isComposing: $isComposing,
                    send: send
                )
            }
            .paletteGround()
            // Read live from the model rather than frozen at init: a new
            // conversation earns its title with its first question, while
            // this screen is the one being watched.
            .navigationTitle(model.title ?? "Coach")
            .navigationBarTitleDisplayMode(.inline)
            // Guarded on the transcript rather than run once, because `.task`
            // runs again every time this screen comes back — popping a session
            // cover, or returning from wherever an offer led. The guard is what
            // stops the question being asked a second time on top of its own
            // answer.
            .task {
                if let opening, model.transcript.isEmpty {
                    model.send(opening)
                }
            }
            // The stream dies with the screen — a request nobody is watching;
            // cancel persists what arrived. Except under the session cover:
            // presenting it fires onDisappear too, and cutting a reply off
            // because the person accepted its own offer would hand them back
            // a truncated answer after the session.
            .onDisappear {
                if started == nil {
                    model.cancel()
                }
            }
            .fullScreenCover(item: $started) { session in
                SessionView(model: session.model)
            }
            .paywall(for: .general, isPresented: $isShowingPaywall)
            // A cover rather than a sheet, matching the door on the Check-ins
            // screen: the test is two minutes of holding still, and a card the
            // transcript shows through is a screen to look away from.
            .fullScreenCover(isPresented: $isTakingBoltTest) {
                NavigationStack {
                    BoltTestView(model: journey)
                }
            }
    }

    private var conversation: some View {
        CoachTranscript(turns: model.transcript, isReplying: model.isReplying, pinned: pinned) {
            row(for: $0)
        }
    }

    /// One turn as a bubble: the person's trailing in a brand-tinted fill, the
    /// coach's leading on the raised surface, neither spanning the full width
    /// so alignment alone says who is speaking. Flat fills, not glass — a
    /// glass layer per bubble would sample a transcript that redraws on every
    /// streamed chunk (the composer's grouping comment tells that story).
    @ViewBuilder
    private func row(for turn: ChatTurn) -> some View {
        switch turn.role {
        case .person:
            bubble(fill: Theme.Accent.brand.opacity(Theme.Fill.selection)) { Text(turn.text) }
                .frame(maxWidth: .infinity, alignment: .trailing)
                .padding(.leading, 2 * Theme.Spacing.loose)
        case .coach:
            VStack(alignment: .leading, spacing: Theme.Spacing.close) {
                // A reply that was only ever its offer draws no bubble: an
                // empty pill above the card would read as a lost message.
                if !turn.text.isEmpty {
                    bubble(fill: Theme.Surface.raised) {
                        RevealingText(
                            turn.text,
                            isStreaming: isRevealing(turn),
                            pace: CoachChatModel.revealTick
                        )
                    }
                }
                proposalCard(for: turn)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.trailing, 2 * Theme.Spacing.loose)
        }
    }

    /// The card a reply ends on, where it ended on one.
    ///
    /// An exercise whose slug this device's catalogue no longer holds draws
    /// nothing at all and the prose stands alone — the drop-don't-retry answer a
    /// stale notification gets, and the reason the coach's words are contracted
    /// to stand without their card.
    @ViewBuilder
    private func proposalCard(for turn: ChatTurn) -> some View {
        switch turn.proposal {
        case let .exercise(offer):
            if let technique = resolve(offer) {
                ExerciseOfferCard(
                    technique: technique.dialled(with: offer.overrides),
                    start: { start(technique, offer: offer) }
                )
            }
        case .boltTest:
            BoltTestOfferCard(start: { isTakingBoltTest = true })
        case let .savedExercise(draft):
            SavedExerciseOfferCard(draft: draft, own: own)
        case nil:
            EmptyView()
        }
    }

    private func bubble(fill: Color, @ViewBuilder content: () -> some View) -> some View {
        content()
            .font(.body)
            .foregroundStyle(Theme.Ink.primary)
            .padding(.horizontal, Theme.Spacing.standard)
            .padding(.vertical, Theme.Spacing.close)
            .background(fill, in: .rect(cornerRadius: Theme.Radius.card))
    }

    /// Whether this turn is the one still being written, which is the only one
    /// whose newest words should arrive behind a soft edge. Every other turn —
    /// the whole transcript above it — was finished before it was drawn.
    private func isRevealing(_ turn: ChatTurn) -> Bool {
        model.isReplying && turn.id == model.transcript.last?.id
    }

    /// The technique an offer names, or nil while the catalogue has not
    /// loaded or no longer holds the slug — in which case no card renders and
    /// the reply's prose stands on its own, the same drop-don't-retry answer
    /// a stale notification gets.
    private func resolve(_ offer: ExerciseOffer) -> Technique? {
        guard case let .loaded(techniques) = catalogue.state else { return nil }
        return techniques.first { $0.slug == offer.techniqueSlug }
    }

    /// Starts the offered exercise, dialled as offered for this session alone
    /// — never written to the person's saved dials: a chat suggestion is
    /// advice for one session, not a settings edit.
    private func start(_ technique: Technique, offer: ExerciseOffer) {
        // Plain and unprescribed: an offer is the coach reshaping an exercise,
        // not a route into a moment, so it carries neither a register nor an
        // occasion of its own.
        let outcome = resolver.resolvePhoneSession(
            technique,
            dialledWith: offer.overrides,
            for: plus.tier
        )
        switch outcome {
        case let .phoneSession(session):
            started = session
        case .subscriptionRequired:
            isShowingPaywall = true
        case .wristHandoff:
            break
        }
    }

    private var resolver: SessionLaunchResolver {
        SessionLaunchResolver(sessions: sessions) {
            SessionCues(
                mode: settings.cueMode,
                strength: settings.hapticStrength,
                sound: settings.sound
            )
        }
    }

    /// Sends, and names the question the transcript should pin to the top.
    ///
    /// Naming it is the whole of what this does about scrolling: `CoachTranscript`
    /// watches the pin and owns everything that follows from it.
    private func send() {
        let message = draft
        draft = ""
        model.send(message)
        pinned = model.transcript.last?.id
    }
}
