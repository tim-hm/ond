import OndKit
import OndUI
import SwiftUI

/// The conversation as a scrolling column, and everything that decides when
/// it may move. A send scrolls its question to the top once; the answer
/// reveals into room already made below, and only an answer that outgrows
/// that room follows the bottom — never while the person has scrolled off.
/// The plain bottom anchor this replaces walked the text being read upward.
struct CoachTranscript<Row: View>: View {
    let turns: [ChatTurn]
    let isReplying: Bool

    /// The question this screen scrolled to the top — the start of the
    /// exchange being watched. Nil until the first send of the visit, so a
    /// resumed conversation opens exactly as it always did. Read, never
    /// written: sending sets it and scrolling answers.
    let pinned: UUID?

    @ViewBuilder let row: (ChatTurn) -> Row

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var position = ScrollPosition(idType: UUID.self)

    /// How tall the watched exchange is, and how much room there is to put it in
    /// — the two numbers that decide both the spacer below it and whether the
    /// answer has outgrown the space reserved for it.
    @State private var watchedHeight: CGFloat = 0
    @State private var viewport: CGFloat = 0

    /// Whether the person has taken the scroll for themselves. Held from the
    /// moment they drag until they come back to the end, which is the only
    /// signal that they are done reading where they were.
    @State private var isFollowingHeld = false

    var body: some View {
        ScrollView {
            LazyVStack(spacing: Theme.Spacing.loose) {
                if turns.isEmpty {
                    invitation
                }

                ForEach(settled) { turn in
                    row(turn)
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
        // Placement on arrival only — the single-argument form governs growth,
        // which is precisely what a streaming reply is. Bottom only once there
        // is something to pin: an empty conversation anchored to the bottom
        // reads as a transcript that scrolled away, not one yet to start.
        .defaultScrollAnchor(turns.isEmpty ? .center : .bottom, for: .initialOffset)
        // Following, when following is what is wanted. Declarative rather than a
        // `scrollTo` per publish, which is the main-thread-work-per-chunk the
        // anchor does for free.
        .defaultScrollAnchor(isFollowing ? .bottom : nil, for: .sizeChanges)
        // The one scroll this screen performs. Driven by the pin changing rather
        // than called from the send, so that everything deciding where the
        // transcript sits lives in one type.
        .onChange(of: pinned) { _, question in
            isFollowingHeld = false
            withAnimation(reduceMotion ? nil : .easeOut(duration: 0.25)) {
                position.scrollTo(id: question, anchor: .top)
            }
        }
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
            // A drag is the person taking the scroll; following an answer they
            // scrolled away from would haul them back mid-sentence. Interactive
            // keyboard dismissal trips this too, but it drags towards the end,
            // so the rule below hands following straight back on the same
            // gesture. Deliberately not special-cased.
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
        // Over the transcript rather than in the composer's stack: the safe-area
        // inset means the bottom of this scroll view already sits above the
        // composer, so an overlay lands clear of the send button without the
        // floating-bar collision `keyboardDismissButton` records.
        .overlay(alignment: .bottom) {
            if isShowingLatest {
                latestButton
                    .padding(.bottom, Theme.Spacing.close)
                    .transition(.opacity)
            }
        }
        .animation(reduceMotion ? nil : .easeOut(duration: 0.2), value: isShowingLatest)
    }

    /// The question that was pinned to the top and whatever is answering it,
    /// measured — and followed by room for an answer not yet written.
    @ViewBuilder
    private var watchedExchange: some View {
        VStack(spacing: Theme.Spacing.loose) {
            ForEach(watched) { turn in
                row(turn)
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

    /// The way back to an answer that has run on past the screen while it was
    /// being read.
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

    /// The turns above the pinned question — everything the person has already
    /// read. Lazy, because a long conversation is mostly this.
    private var settled: ArraySlice<ChatTurn> {
        turns.prefix(turns.count - watched.count)
    }

    /// The exchange being watched, or nothing at all before the first send of
    /// this visit — which is what makes a resumed conversation need no branch of
    /// its own: no pin, no measured exchange, no spacer, and the initial anchor
    /// opens it on its last turn exactly as before.
    private var watched: ArraySlice<ChatTurn> {
        guard let pinned, let index = turns.firstIndex(where: { $0.id == pinned }) else {
            return []
        }
        return turns[index...]
    }

    /// Whether an arriving answer has outgrown the room reserved for it —
    /// until then it is filling a spacer and nothing needs to move. Written
    /// once because the two rules below are its two sides: the transcript
    /// follows the end, or it offers the way back to it.
    private var isOverflowing: Bool {
        isReplying && watchedHeight > viewport
    }

    /// Whether the transcript should climb as the answer grows — only while the
    /// person has not taken the scroll themselves.
    private var isFollowing: Bool {
        isOverflowing && !isFollowingHeld
    }

    /// The gap between the question being sent and the first words of its
    /// answer, which is the one moment on this screen with nothing to show.
    private var isThinking: Bool {
        isReplying && turns.last?.role == .person
    }

    /// Offered only when there is genuinely unseen answer below — not merely
    /// whenever the scroll is off the end, because under this design it is off
    /// the end for most of every reply, and a control that is always up is
    /// chrome rather than an affordance.
    private var isShowingLatest: Bool {
        isOverflowing && isFollowingHeld
    }

    /// What an empty conversation says instead of blank space. Never seen with
    /// an `opening` question — that first turn is sent before the first frame,
    /// and an invitation to ask something, above a question already asked,
    /// would be the screen talking over itself.
    private var invitation: some View {
        Text(
            "Ask about your practice — which exercise fits how you slept, "
                + "what your breath test means, where to go next."
        )
        .font(.body)
        .foregroundStyle(Theme.Ink.tertiary)
    }
}
