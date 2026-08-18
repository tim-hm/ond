#if os(iOS)
    import SwiftUI

    public extension View {
        /// A raised surface, drawn on glass.
        ///
        /// The counterpart to `paletteGround()`: that one grounds a screen, this
        /// one lifts a card off it. Both live here rather than beside the views
        /// that call them, because a card recipe copied into each feature is how a
        /// second visual vocabulary starts.
        ///
        /// Glass rather than the flat `Surface.raised` fill and hairline it
        /// replaces, for a reason beyond the material being the platform's: a
        /// selected state becomes one property instead of a fill and a stroke that
        /// have to be kept agreeing.
        ///
        /// **On `Surface.raised`, not on the ground.** Glass takes its luminance
        /// from whatever is behind it, so a card left to sample the ground came
        /// out the same grey as the ground — the refresh draws white cards, and
        /// the white has to be put there. The material stays on top of it for the
        /// press, the specular edge, and the tint. `Theme.Shadow` then does the
        /// separating, because white on the light ground is 1.14:1 and has no
        /// edge of its own.
        ///
        /// The plate goes *behind* the applied material rather than under it as
        /// a background of the same view, and that ordering is not a style: put
        /// the fill inside and the glass has an opaque white in front of it and
        /// disappears. The cost is that an `interactive:` press flexes the
        /// material over a plate that does not move with it. Owed a device
        /// check — the simulator's glass is not the phone's.
        ///
        /// Untinted for everything but selection. A goal's colour lives in
        /// marks — a dot, a figure, a word — at full strength, never in the
        /// card's fill: diluted to a strength a fill can carry, two neighbouring
        /// accents stop being tellable apart, and the tint reads as decoration
        /// rather than information.
        ///
        /// - Parameters:
        ///   - accent: The colour to tint the glass with, or nil to leave it
        ///     untinted. Selection is the tint's presence rather than a change in
        ///     its strength, so a card has one value to pass and no second state to
        ///     get wrong.
        ///   - interactive: Whether the glass should answer a press with the
        ///     material's own flex and highlight. True where the card is itself a
        ///     button — a `plain`-styled button over a flat fill has nothing that
        ///     moves under a finger — and false where it merely holds a control,
        ///     which would otherwise flex when the control inside it was the thing
        ///     being touched.
        ///   - raised: Whether to put `Surface.raised` and a shadow under the
        ///     material. True for a card on a screen's flat ground, which is
        ///     nearly all of them. False for the two that float over a ground
        ///     with something to show through it — the summary over the
        ///     session's accent wash, the coach's notice over its radial and a
        ///     live transcript — where an opaque fill is exactly what those
        ///     screens went to glass to avoid.
        func glassCard(
            tinted accent: Color? = nil,
            interactive: Bool = false,
            raised: Bool = true
        ) -> some View {
            var glass = Glass.regular

            if let accent {
                glass = glass.tint(accent.opacity(Theme.Glass.selection))
            }

            if interactive {
                glass = glass.interactive()
            }

            return glassEffect(glass, in: .rect(cornerRadius: Theme.Radius.card))
                .background {
                    if raised {
                        RoundedRectangle(cornerRadius: Theme.Radius.card)
                            .fill(Theme.Surface.raised.shadow(Theme.Shadow.list))
                    }
                }
        }
    }
#endif
