#if os(iOS)
    import SwiftUI

    public extension View {
        /// A raised surface, drawn on glass. The plate is `Surface.raised`, because
        /// glass takes its luminance from behind — a card left to sample the ground
        /// comes out ground-grey. The plate goes *behind* the applied material: a fill
        /// inside puts opaque white in front and the glass disappears. Tint marks
        /// selection; `interactive:` only where the card is itself the button.
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
