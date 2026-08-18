import OndKit
import OndUI
import SwiftUI

/// What Home offers under the lead: one card, a row per practice, and the way
/// to the rest at the bottom of it.
///
/// Four separate cards became one. Stacked eight points apart they read as four
/// unrelated offers each competing for the same tap, and the screen's shape was
/// a list of cards rather than a screen with a shelf on it. The hairlines now do
/// the separating the gaps used to, at a fraction of the room.
///
/// "All exercises" is a row *inside* the card rather than a door below it, for
/// the same reason: it is where this list continues, not a second destination.
/// It is `DoorCard` all the same — that type stopped drawing its own surface so
/// this could be the shape it already is, rather than a fourth hand-copy of a
/// title, a chevron and a tap target.
///
/// What the card holds is `HomeShelf.practices`', not this view's: the stars
/// first and the catalogue behind them, which is a claim about somebody's
/// choices and belongs where it can be tested.
struct PracticesCard: View {
    let practices: [DialStop]
    let tier: SubscriptionTier

    /// Begins the stop a row names.
    let start: (DialStop) -> Void

    /// What the last row does. A closure because the other side is the
    /// Exercises *tab*, which no `NavigationLink` in this stack can reach.
    let openExercises: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            ForEach(practices) { stop in
                StopRow(stop: stop, tier: tier) { start(stop) }
                hairline
            }

            allExercises
        }
        // Not interactive: the card holds the buttons rather than being one, and
        // interactive glass would flex the whole shelf when a single row was
        // pressed.
        .glassCard()
    }

    /// The rule between two rows. `Divider` tinted to the hairline, which is
    /// what the two other row lists in the app draw (`PracticeProgressView`,
    /// `LeaderboardView`) — full-bleed rather than inset to the title, because
    /// the star sits at the far end of the row and a rule stopping short of it
    /// would read as a ragged edge rather than a separator.
    private var hairline: some View {
        Divider().overlay(Theme.Surface.line)
    }

    /// The last row: everything the card had no space for. A door with no
    /// caption, which is the compact form that type already draws.
    private var allExercises: some View {
        DoorCard(title: "All exercises", action: openExercises)
            .accessibilityHint("Opens the Exercises tab")
            .accessibilityIdentifier("all-exercises-row")
    }
}
