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
    /// and lands on the Journey tab like one taken from its own door. From the
    /// environment rather than threaded: this screen sits four views below the
    /// tab that owns it on one of its two routes in, and the three screens
    /// between do not otherwise know it exists.
    @Environment(JourneyModel.self) private var journey

    /// The person's own exercises, which a save-this-pattern card writes into.
    /// From the environment for the same reason the journey is.
    @Environment(UserTechniqueModel.self) private var own
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var model: CoachChatModel
    @State private var draft = ""
    @State private var started: StartedSession?
    @State private var locked: Technique?
    @State private var isTakingBoltTest = false

    @State private var position = ScrollPosition(idType: UUID.self)

    /// The question this screen scrolled to the top, and therefore the start of
    /// the exchange being watched. Nil until the first send of the visit, which
    /// is what leaves a resumed conversation opening exactly as it always did.
    @State private var pinned: UUID?

    /// How tall that exchange is, and how much room there is to put it in — the
    /// two numbers that decide both the spacer below it and whether the answer
    /// has outgrown the space reserved for it.
    @State private var watchedHeight: CGFloat = 0
    @State private var viewport: CGFloat = 0

    /// Whether the person has taken the scroll for themselves. Held from the
    /// moment they drag until they come back to the end, which is the only
    /// signal that they are done reading where they were.
    @State private var isFollowingHeld = false

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
            // A cover rather than a sheet, matching the door on the Check-ins
            // screen: the test is two minutes of holding still, and a card the
            // transcript shows through is a screen to look away from.
            .fullScreenCover(isPresented: $isTakingBoltTest) {
                NavigationStack {
                    BoltTestView(model: journey)
                }
            }
    }

    /// The transcript, which holds still while it is being read.
    ///
    /// A send scrolls the question to the top once, and after that nothing
    /// moves: the answer reveals into room already made for it below. Only an
    /// answer that outgrows that room follows the bottom, and only while the
    /// person has not scrolled off somewhere themselves. What this replaces is
    /// a plain bottom anchor, which climbed on every republish and walked the
    /// paragraph being read up out from under the eye.
    private var conversation: some View {
        ScrollView {
            LazyVStack(spacing: Theme.Spacing.loose) {
                if model.transcript.isEmpty {
                    invitation
                }

                ForEach(settled) { turn in
                    row(for: turn)
                }

                if !watched.isEmpty {
                    watchedExchange
                }
            }
            .scrollTargetLayout()
            .padding(.horizontal, Theme.Spacing.standard)
            .padding(.vertical, Theme.Spacing.loose)
        }
        .scrollDismissesKeyboard(.interactively)
        .scrollPosition($position)
        // Placement on arrival only. The single-argument form governs growth as
        // well, and growth is precisely what a streaming reply is.
        //
        // Bottom only once there is something to pin: an empty conversation
        // anchored to the bottom presses its one paragraph against the composer
        // with the whole screen empty above it, which reads as a transcript that
        // scrolled away rather than one that has not started.
        .defaultScrollAnchor(model.transcript.isEmpty ? .center : .bottom, for: .initialOffset)
        // Following, when following is what is wanted. Declarative rather than a
        // `scrollTo` per publish, which is the main-thread-work-per-chunk the
        // anchor does for free.
        .defaultScrollAnchor(isFollowing ? .bottom : nil, for: .sizeChanges)
        .onScrollGeometryChange(for: CGFloat.self) { geometry in
            // The usable height, not the container's: the composer is a safe-area
            // inset and arrives here as a content inset, so the raw height would
            // reserve room the composer is standing on.
            geometry.containerSize.height - geometry.contentInsets.top
                - geometry.contentInsets.bottom
        } action: { _, height in
            viewport = height
        }
        .onScrollPhaseChange { _, phase in
            // A drag is the person taking the scroll. Following an answer they
            // have scrolled away from would haul them back mid-sentence, which
            // is the one thing worse than not following at all.
            //
            // Interactive keyboard dismissal is a drag too, and so trips this.
            // It is a downward drag — towards the end — so the rule below hands
            // following straight back on the same gesture. Deliberately not
            // special-cased.
            if phase == .interacting {
                isFollowingHeld = true
            }
        }
        .onScrollGeometryChange(for: Bool.self) { geometry in
            // The slack is what stops a rest a few points short of the end
            // reading as "scrolled away" for the remainder of the reply.
            geometry.visibleRect.maxY >= geometry.contentSize.height - Theme.Spacing.loose
        } action: { _, isAtEnd in
            if isAtEnd {
                isFollowingHeld = false
            }
        }
    }

    /// The question that was pinned to the top and whatever is answering it,
    /// measured — and followed by room for an answer not yet written.
    @ViewBuilder
    private var watchedExchange: some View {
        VStack(spacing: Theme.Spacing.loose) {
            ForEach(watched) { turn in
                row(for: turn)
            }

            if isThinking {
                ThinkingDot()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.trailing, 2 * Theme.Spacing.loose)
                    .transition(.opacity)
            }
        }
        .animation(reduceMotion ? nil : .easeOut(duration: 0.2), value: isThinking)
        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { watchedHeight = $0 }

        // What makes pinning a one-line question to the top possible at all:
        // room below it for an answer nobody has written yet. Sized to what
        // the exchange has not already filled, so it shrinks away as the
        // answer grows and never leaves a screen of blank to scroll into.
        Color.clear.frame(height: max(0, viewport - watchedHeight))
    }

    /// The turns above the pinned question — everything the person has already
    /// read. Lazy, because a long conversation is mostly this.
    private var settled: ArraySlice<ChatTurn> {
        model.transcript.prefix(model.transcript.count - watched.count)
    }

    /// The exchange being watched, or nothing at all before the first send of
    /// this visit — which is what makes a resumed conversation need no branch of
    /// its own: no pin, no measured exchange, no spacer, and the initial anchor
    /// opens it on its last turn exactly as before.
    private var watched: ArraySlice<ChatTurn> {
        guard let pinned,
              let index = model.transcript.firstIndex(where: { $0.id == pinned })
        else {
            return []
        }
        return model.transcript[index...]
    }

    /// Whether the transcript should climb as the answer grows: only while one
    /// is arriving, only once it has outgrown the room reserved for it — until
    /// then it is filling a spacer and nothing needs to move — and only while
    /// the person has not taken the scroll themselves.
    private var isFollowing: Bool {
        model.isReplying && watchedHeight > viewport && !isFollowingHeld
    }

    /// The gap between the question being sent and the first words of its
    /// answer, which is the one moment on this screen with nothing to show.
    private var isThinking: Bool {
        model.isReplying && model.transcript.last?.role == .person
    }

    /// Offered only when there is genuinely unseen answer below — not merely
    /// whenever the scroll is off the end, because under this design it is off
    /// the end for most of every reply, and a control that is always up is
    /// chrome rather than an affordance.
    private var isShowingLatest: Bool {
        model.isReplying && isFollowingHeld && watchedHeight > viewport
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
            bubble(fill: Theme.Accent.brand.opacity(0.18)) { Text(turn.text) }
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

            if isShowingLatest {
                latestButton
                    .transition(.opacity)
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
        .animation(reduceMotion ? nil : .easeOut(duration: 0.2), value: isShowingLatest)
    }

    /// The way back to an answer that has run on past the screen while it was
    /// being read.
    ///
    /// In the composer's own stack rather than a `.keyboard` toolbar, for the
    /// reason `keyboardDismissButton` records: a floating bar in that band lands
    /// on top of the send button.
    private var latestButton: some View {
        Button {
            isFollowingHeld = false
            withAnimation(reduceMotion ? nil : .easeOut(duration: 0.25)) {
                position.scrollTo(edge: .bottom)
            }
        } label: {
            Label("Latest", systemImage: "chevron.down")
                .font(.footnote.weight(.semibold))
                .padding(.horizontal, Theme.Spacing.standard)
                .padding(.vertical, Theme.Spacing.close)
        }
        .buttonStyle(.plain)
        .foregroundStyle(Theme.Ink.secondary)
        .glassEffect(in: .capsule)
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

        // The one scroll on this screen. The question goes to the top and stays
        // there while the answer fills the space below it; everything after this
        // is content arriving into room already made.
        //
        // Following is handed back here rather than left held, because sending
        // is the person saying they are done reading wherever they had scrolled.
        isFollowingHeld = false
        pinned = model.transcript.last?.id
        withAnimation(reduceMotion ? nil : .easeOut(duration: 0.25)) {
            position.scrollTo(id: pinned, anchor: .top)
        }
    }
}
