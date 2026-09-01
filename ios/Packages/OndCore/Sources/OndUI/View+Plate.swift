import SwiftUI

public extension View {
    /// An opaque grouped-list plate: the surface a stack of hairline-separated
    /// rows sits on. The opaque counterpart of `glassCard()`, and it shares
    /// that recipe's fill and shadow — `Surface.raised` is 1.14:1 against the
    /// light ground, so the shadow is what gives the plate an edge at all.
    /// Rows draw their own dividers; this draws only the surface under them.
    func plate() -> some View {
        background {
            RoundedRectangle(cornerRadius: Theme.Radius.card)
                .fill(Theme.Surface.raised.shadow(Theme.Shadow.list))
        }
        .overlay {
            RoundedRectangle(cornerRadius: Theme.Radius.card)
                .stroke(Theme.Surface.line, lineWidth: 0.5)
        }
    }
}
