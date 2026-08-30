import OndKit
import OndUI
import SwiftUI

/// The bar the person types into, and the notice for a subscription the
/// server has not seen yet. The half of the chat screen with no stake in the
/// transcript: it reads what the model is doing and reports what was typed,
/// and knows nothing about where the conversation is scrolled to.
struct CoachComposer: View {
    @Binding var draft: String

    /// Disables send — not the field — so the next question can be typed over a
    /// streaming answer.
    let isReplying: Bool

    /// Where the newest reply came from, which is the whole of what raises the
    /// confirming notice.
    let lastReplySource: GuidanceSource?

    /// Whether the field holds the keyboard, owned by the screen because the
    /// transcript's dismissal gesture acts on it too.
    @FocusState.Binding var isComposing: Bool

    let send: () -> Void

    @Environment(SubscriptionStore.self) private var plus

    /// Read so the send glyph dims when an ancestor disables the whole
    /// composer, which is how `CoachOffer` draws the free tier. The system
    /// button this replaced took that from the environment for free.
    @Environment(\.isEnabled) private var isEnabled

    /// The bar's resting height, which the refresh spec sets.
    private static let barHeight: CGFloat = 48

    /// The send circle the eye sees, inside a tap target half again its size —
    /// the proportion Messages and Mail draw a send button at.
    private static let sendGlyph: CGFloat = 30

    var body: some View {
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

    /// The server just answered "subscription required" to somebody who holds
    /// Coach (`CoachRootView` is the gate) — uniquely a purchase the server
    /// has not seen. Above the composer rather than replacing it: the state
    /// is usually brief, and a screen that empties itself reads as a failure.
    private var isAwaitingEntitlement: Bool {
        lastReplySource == .subscriptionRequired
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
                .foregroundStyle(Theme.Accent.brandText)
            }
        }
        .padding(Theme.Spacing.standard)
        // Unraised, like the bar below it: this notice floats over the coach's
        // radial ground and a moving transcript, and an opaque fill would make
        // the two halves of one floating stack different materials.
        .glassCard(raised: false)
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

            sendButton
        }
        .frame(minHeight: Self.barHeight)
        // Asymmetric: the field wants a full inset to read as text, while the
        // send glyph already stands clear inside its own tap target.
        .padding(EdgeInsets(
            top: Theme.Spacing.tight,
            leading: Theme.Spacing.standard,
            bottom: Theme.Spacing.tight,
            trailing: Theme.Spacing.close
        ))
        // A capsule of the tab bar's own material, floating clear of it, rather
        // than a flat full-width strip stacked on top: two opaque slabs read as
        // two pieces of chrome, where this reads as one system with the bar.
        .glassEffect(in: .capsule)
    }

    /// A filled glyph rather than a circular `glassProminent` button: that
    /// button drew its own material inside the bar's, and two glass layers one
    /// within the other read as a blob rather than a control. The palette
    /// rendering carries "off" in the circle's own colour — dimming the whole
    /// glyph fades the arrow with it, leaving nothing to read.
    private var sendButton: some View {
        let isReady = canSend && isEnabled

        return Button(action: send) {
            Image(systemName: "arrow.up.circle.fill")
                .font(.system(size: Self.sendGlyph))
                .symbolRenderingMode(.palette)
                .foregroundStyle(
                    Theme.Surface.ground,
                    isReady ? Theme.Breath.inhale : Theme.Ink.tertiary
                )
                // The circle is smaller than a finger; the target is not.
                .frame(
                    width: Theme.Metrics.minimumTapTarget,
                    height: Theme.Metrics.minimumTapTarget
                )
                .contentShape(.circle)
        }
        .buttonStyle(.plain)
        .disabled(!isReady)
        .accessibilityLabel("Send")
    }

    /// The way off the screen while the keyboard is up. In the composer rather
    /// than a `.keyboard` toolbar: a toolbar is a second floating capsule in
    /// the same band, and it lands on top of the send button. Only while
    /// composing — the keyboard covers the tab bar, and the state people get
    /// stuck in is the one with no way off.
    private var keyboardDismissButton: some View {
        Button {
            isComposing = false
        } label: {
            Image(systemName: "keyboard.chevron.compact.down")
                // A full minimum target: the bare glyph is about half this and
                // reads as something a person has to aim at.
                .frame(
                    width: Theme.Metrics.minimumTapTarget,
                    height: Theme.Metrics.minimumTapTarget
                )
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .foregroundStyle(Theme.Ink.secondary)
        .accessibilityLabel("Put the keyboard away")
    }

    private var canSend: Bool {
        !isReplying && !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}
