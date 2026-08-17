import SwiftUI

public extension View {
    /// The small uppercase line that names what sits above a card's content —
    /// "Continue", "From your watch", a goal word over a coach offer.
    ///
    /// One recipe rather than a font stack per card, because three surfaces
    /// were already carrying byte-identical copies of it and an eyebrow that
    /// drifted a weight between two cards on one screen would read as two
    /// different kinds of label.
    ///
    /// - Parameter color: The ink the line is set in. Tertiary by default —
    ///   an eyebrow is quieter than what it introduces — and a goal's
    ///   `textAccent` where the line is the card's one colour mark.
    func eyebrow(_ color: Color = Theme.Ink.tertiary) -> some View {
        font(.caption.weight(.semibold))
            .textCase(.uppercase)
            .foregroundStyle(color)
    }
}
