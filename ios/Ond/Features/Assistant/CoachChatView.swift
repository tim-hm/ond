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

    @State private var model: CoachChatModel
    @State private var draft = ""
    @State private var started: StartedSession?
    @State private var locked: Technique?

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
            .safeAreaInset(edge: .bottom) { composer }
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
            .sheet(item: $locked) { technique in
                PaywallView(highlighting: technique.requires)
            }
    }

    private var conversation: some View {
        ScrollView {
            LazyVStack(spacing: Theme.Spacing.loose) {
                if model.transcript.isEmpty {
                    invitation
                }

                ForEach(model.transcript) { turn in
                    row(for: turn)
                }
            }
            .padding(.horizontal, Theme.Spacing.standard)
            .padding(.vertical, Theme.Spacing.loose)
        }
        .scrollDismissesKeyboard(.interactively)
        // Pinned to the bottom by the anchor rather than driven by a
        // `scrollTo` per chunk: the transcript republishes on every streamed
        // chunk, and a per-chunk scroll request is main-thread work the
        // anchor does for free.
        //
        // Only once there is something to pin. An empty conversation anchored
        // to the bottom presses its one paragraph against the composer with the
        // whole screen empty above it, which reads as a transcript that scrolled
        // away rather than one that has not started.
        .defaultScrollAnchor(model.transcript.isEmpty ? .center : .bottom)
    }

    /// What an empty conversation says instead of blank space: what the coach
    /// is for, in the coach's register, gone the moment there is a transcript.
    ///
    /// Never seen by a conversation that arrived with an `opening` question — its
    /// first turn is sent before the first frame, so the transcript is already not
    /// empty. An invitation to ask something, above a question already asked,
    /// would be the screen talking over itself.
    private var invitation: some View {
        Text(
            "Ask about your practice — which exercise fits how you slept, "
                + "what your breath test means, where to go next."
        )
        .font(.body)
        .foregroundStyle(Theme.Ink.tertiary)
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
            bubble(turn.text, fill: Theme.Accent.brand.opacity(0.18))
                .frame(maxWidth: .infinity, alignment: .trailing)
                .padding(.leading, 2 * Theme.Spacing.loose)
        case .coach:
            VStack(alignment: .leading, spacing: Theme.Spacing.close) {
                // A reply that was only ever its offer draws no bubble: an
                // empty pill above the card would read as a lost message.
                if !turn.text.isEmpty {
                    bubble(turn.text, fill: Theme.Surface.raised)
                }
                if let offer = turn.offer, let technique = resolve(offer) {
                    ExerciseOfferCard(
                        technique: technique.dialled(with: offer.overrides),
                        start: { start(technique, offer: offer) }
                    )
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.trailing, 2 * Theme.Spacing.loose)
        }
    }

    private func bubble(_ text: String, fill: Color) -> some View {
        Text(text)
            .font(.body)
            .foregroundStyle(Theme.Ink.primary)
            .padding(.horizontal, Theme.Spacing.standard)
            .padding(.vertical, Theme.Spacing.close)
            .background(fill, in: .rect(cornerRadius: Theme.Radius.card))
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
        let start = SessionStart(sessions: sessions, settings: settings, tier: plus.tier)
        guard let session = start.session(for: technique, dialledWith: offer.overrides) else {
            locked = technique
            return
        }
        started = StartedSession(model: session)
    }

    private var composer: some View {
        VStack(spacing: Theme.Spacing.close) {
            if isAwaitingEntitlement {
                confirmingNotice
            }

            // The bar and the send button are both glass, so they are grouped:
            // two ungrouped layers sample their own backdrop, and this backdrop
            // is the transcript scrolling underneath, redrawn on every streamed
            // chunk.
            GlassEffectContainer {
                bar
            }
        }
        .padding(.horizontal, Theme.Spacing.standard)
        .padding(.bottom, Theme.Spacing.close)
    }

    /// The third state the screen used to have no word for: the server just
    /// answered "subscription required" to somebody this screen only exists
    /// for because they hold Coach (`CoachRootView` is the gate) — uniquely a
    /// purchase the server has not seen. Above the composer rather than
    /// replacing it: the state is usually brief, and a screen that empties
    /// itself reads as a failure.
    private var isAwaitingEntitlement: Bool {
        model.lastReplySource == .subscriptionRequired
    }

    private var confirmingNotice: some View {
        HStack(alignment: .firstTextBaseline, spacing: Theme.Spacing.close) {
            Text(confirmingCopy)
                .font(.footnote)
                .foregroundStyle(Theme.Ink.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)

            // A locally signed purchase can never confirm, and a held one
            // confirms by waiting — so no button that implies pressing it
            // might help either along.
            if plus.lastSubmission != .refusedLocallySigned, plus.lastSubmission != .held {
                Button("Retry") {
                    Task { await plus.resubmit() }
                }
                .font(.footnote.weight(.semibold))
                .buttonStyle(.plain)
                .foregroundStyle(Theme.Accent.brand)
            }
        }
        .padding(Theme.Spacing.standard)
        .glassCard()
    }

    /// Which of the four shades of "not confirmed yet" this is. The upgrade
    /// pitch is deliberately absent from all of them: everyone who can read
    /// this has already bought the thing an upsell would offer.
    private var confirmingCopy: String {
        switch plus.lastSubmission {
        case .refusedLocallySigned:
            "Purchases on this build stay local to Xcode and never reach "
                + "the server, so the coach answers from its rules here."
        case .refused:
            "Your subscription couldn't be confirmed. Nothing more has been "
                + "charged — retry, and contact support if it keeps happening."
        case .held:
            "Your subscription is settling onto this device — a safeguard "
                + "after a reinstall holds it for up to a day. Nothing is "
                + "broken, and no action is needed."
        case nil:
            "Confirming your subscription with the App Store. The coach "
                + "answers from its rules until that lands."
        }
    }

    private var bar: some View {
        HStack(spacing: Theme.Spacing.close) {
            if isComposing {
                keyboardDismissButton
            }

            // Deliberately no `.onSubmit`: `axis: .vertical` makes Return a
            // newline key, the modifier never fires, and one that reads as
            // wired-up while doing nothing is worse than its absence. The send
            // button is the way to send, which is the bargain every multi-line
            // composer strikes.
            TextField("Ask the coach", text: $draft, axis: .vertical)
                .lineLimit(1 ... 4)
                .textFieldStyle(.plain)
                .focused($isComposing)
                // The intent note's pattern: clamp as typed, so a long paste
                // can never become a refused request that reads as the
                // network failing. Counted in Unicode scalars — the server's
                // unit — because 1000 Characters of emoji is more scalars
                // than the server accepts.
                .onChange(of: draft) { _, text in
                    if text.unicodeScalars.count > ChatTurn.maxMessageLength {
                        draft = String(String.UnicodeScalarView(
                            text.unicodeScalars.prefix(ChatTurn.maxMessageLength)
                        ))
                    }
                }

            // Disabled while a reply streams — the composer itself stays
            // live, so the next question can be typed over the answer.
            //
            // A button rather than a tinted glyph: `glassProminent` carries its
            // own disabled state, so nothing here has to decide what "off"
            // looks like, and it sits in the same material as the bar around it.
            Button(action: send) {
                Image(systemName: "arrow.up")
                    .fontWeight(.semibold)
            }
            .buttonStyle(.glassProminent)
            .buttonBorderShape(.circle)
            .tint(Theme.Accent.brand)
            .disabled(!canSend)
            .accessibilityLabel("Send")
        }
        // Asymmetric: the field wants a full inset to read as text, the button
        // only wants clearance from the capsule's edge.
        .padding(EdgeInsets(
            top: Theme.Spacing.tight,
            leading: Theme.Spacing.standard,
            bottom: Theme.Spacing.tight,
            trailing: Theme.Spacing.tight
        ))
        // A capsule of the tab bar's own material, floating clear of it, rather
        // than a flat full-width strip stacked on top: two opaque slabs read as
        // two pieces of chrome, where this reads as one system with the bar.
        .glassEffect(in: .capsule)
    }

    /// The way off the screen while the keyboard is up, and the reason it lives
    /// in the composer rather than in a `.keyboard` toolbar: the composer is
    /// already the bar pinned above the keyboard, and a toolbar is a second
    /// floating capsule in that same band — it lands on top of the send button.
    ///
    /// Only while composing. The keyboard covers the tab bar, the interactive
    /// scroll dismissal on the transcript needs turns to drag against, and the
    /// state people get stuck in is the one with none.
    private var keyboardDismissButton: some View {
        Button {
            isComposing = false
        } label: {
            Image(systemName: "keyboard.chevron.compact.down")
                // The send button's own footprint, so the two controls on this
                // bar are equally hittable. A bare glyph is about half this and
                // reads as a target you have to aim at.
                .frame(width: 32, height: 32)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .foregroundStyle(Theme.Ink.secondary)
        .accessibilityLabel("Put the keyboard away")
    }

    private var canSend: Bool {
        !model.isReplying
            && !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func send() {
        let message = draft
        draft = ""
        model.send(message)
    }
}
