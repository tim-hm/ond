import OndKit
import OndUI
import SwiftUI

// The shell every card that starts a stop wears: whatever the card has to say,
// made one tappable region that begins the session, with the star beside it.
//
// Three decisions, kept apart from what the card says: what the whole card
// does when pressed, what VoiceOver hears before that tap, and where the
// star lives. `ProtocolCard` is the one card wearing it.
//
// **The surface is the caller's.** A protocol is a card and draws its own
// glass, and a shell that drew material of its own would put glass under
// glass the day a row inside a card wore it. So this shell has an opinion
// about the padding and none about the material.
//
// The spoken label is set here for the reason it has always been set on a row:
// a label on a button *replaces* every label composed underneath it —
// including the "· Plus" and "· on your watch" marks a caption carries as
// glyphs for a sighted reader — so the sentence has to be written out, once,
// by whoever owns the tap.

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
