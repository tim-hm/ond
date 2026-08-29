import SwiftUI

public extension View {
    /// The small uppercase line that names what sits above a card's content.
    /// One recipe rather than a font stack per card: three surfaces carried
    /// byte-identical copies, and a drifted weight reads as two kinds of label.
    /// `color` is tertiary by default — an eyebrow is quieter than what it
    /// introduces — and a goal's `textAccent` where the line is the colour mark.
    func eyebrow(_ color: Color = Theme.Ink.tertiary) -> some View {
        font(.caption.weight(.semibold))
            .textCase(.uppercase)
            .foregroundStyle(color)
    }
}
