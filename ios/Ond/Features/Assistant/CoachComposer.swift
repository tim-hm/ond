import OndKit
import OndUI
import SwiftUI

/// The bar the person types into, and the two things that sit above it: the
/// notice for a subscription the server has not seen yet, and nothing else.
///
/// Its own type because the screen it sits on had outgrown one file, and this is
/// the half of it with no stake in the transcript — it reads what the model is
/// doing and reports what was typed, and knows nothing about where the
/// conversation is scrolled to.
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

    /// The third state the screen used to have no word for: the server just
    /// answered "subscription required" to somebody this screen only exists
    /// for because they hold Coach (`CoachRootView` is the gate) — uniquely a
    /// purchase the server has not seen. Above the composer rather than
    /// replacing it: the state is usually brief, and a screen that empties
    /// itself reads as a failure.
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
        !isReplying && !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}
