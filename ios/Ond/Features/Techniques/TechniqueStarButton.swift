import OndKit
import SwiftUI

/// Keep this one near the top.
///
/// Home's sheet offers the default and what the onboarding goal implies, and
/// until this existed that was the only way onto it: an exercise no goal
/// reaches for could be found in Exercises, breathed daily and never pinned. A
/// star is the one instruction that argument does not answer — "that one,
/// whatever the goal says".
///
/// Its own type rather than a property on the detail screen, which is the same
/// containment `TechniqueCoachDoor` has and for a sharper reason: reading
/// `starred` from inside that screen's body would tie the screen to the star set,
/// and its body builds `BreathRhythmChart`, whose init lays out every figure. A
/// star tapped on the Breathe board two tabs away would then redraw the figures of
/// an exercise nobody is looking at.
///
/// It reads and writes different things on purpose, because the board and this
/// bar do not mean the same thing by a star. The board stars a *card*; this stars
/// an *exercise*. So it fills against every card that stands for this exercise —
/// `DialStop.ids(standingFor:)`, which is what makes an exercise starred under
/// an older band read as starred here — and clears all of them, while starring
/// writes the one card the exercise carries in its own right, `DialStop.id(of:)`,
/// the same join the composer makes and the one `HomeOffer` matches against.
struct TechniqueStarButton: View {
    let technique: Technique

    @Environment(StarredStopStore.self) private var stars

    var body: some View {
        let cards = DialStop.ids(standingFor: technique)
        let isStarred = !stars.starred.isDisjoint(with: cards)

        // Fill rather than colour, which the board's star can afford and this
        // cannot: a toolbar item already wears the app's tint, so a brand-coloured
        // glyph would be a control with no visible state. The bar owns the hit
        // target and the metrics too — the 44pt frame the board's star sets by hand
        // would draw a shape this bar did not size.
        return Button {
            if isStarred {
                stars.unstar(cards)
            } else {
                stars.star(DialStop.id(of: technique))
            }
        } label: {
            Label("Star", systemImage: isStarred ? "star.fill" : "star")
                .contentTransition(.symbolEffect(.replace))
        }
        .accessibilityLabel(isStarred ? "Unstar \(technique.name)" : "Star \(technique.name)")
    }
}
