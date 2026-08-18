import OndKit
import OndUI
import SwiftUI

/// The shell every card that starts a stop wears: whatever the card has to say,
/// made one tappable region that begins the session, with the star beside it.
///
/// Home's rows and the Protocols list's cards say different things — one is
/// titled by the exercise and states two facts, the other is titled by the
/// moment and carries a summary, its mechanics and a goal chip — but the shell
/// around them is the same three decisions: what the whole card does when
/// pressed, what VoiceOver hears before that tap, and where the star lives.
/// Written twice, those drift; `StopRow`'s history is a record of exactly that
/// happening once already, between two screens that had a row each.
///
/// **The surface is the caller's.** A protocol is a card and draws its own
/// glass; a Home row is one of four inside a single practices card, and glass
/// under glass would draw a card per row on a card. So this shell has an
/// opinion about the padding — a row and a card sit at the same inset either
/// way — and none about the material.
///
/// The spoken label is set here for the reason it has always been set on a row:
/// a label on a button *replaces* every label composed underneath it —
/// including the "· Plus" and "· on your watch" marks a caption carries as
/// glyphs for a sighted reader — so the sentence has to be written out, once,
/// by whoever owns the tap.
///
/// At `ios/Ond/` on `StopStarButton`'s reasoning: two features draw it and
/// neither owns it. It cannot go on to `OndUI`, which knows nothing about a
/// `DialStop` and must not learn.
struct StartableStopCard<Content: View>: View {
    let stop: DialStop
    let tier: SubscriptionTier
    let start: () -> Void

    @ViewBuilder let content: () -> Content

    @Environment(StarredStopStore.self) private var stars

    var body: some View {
        HStack(alignment: .top, spacing: Theme.Spacing.standard) {
            Button(action: start) {
                content()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    // Inside the button, where the hit region is: the padding
                    // used to sit on the row and left a sixteen-point dead band
                    // above and below every title. It was survivable while each
                    // row was its own card with a gap around it; flush in one
                    // card it means half the space between two hairlines
                    // answers to nothing.
                    .padding(.leading, Theme.Spacing.standard)
                    .padding(.vertical, Theme.Spacing.standard)
                    .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(stop.spokenLabel(for: tier))
            .accessibilityHint("Starts the session")

            StopStarButton(stop: stop, isStarred: stars.isStarred(stop)) {
                stars.toggle(stop)
            }
            // The same inset the words take, so the star stays where it was
            // when the row wore this padding as a whole.
            .padding(.vertical, Theme.Spacing.standard)
        }
    }
}
