import SwiftUI

/// Stretches scroll content to the height its scroller offers, so a
/// one-breath screen (the first-run greeting, Home) centres instead of
/// hugging the toolbar. A `minHeight`, not a fixed frame: at the largest
/// Dynamic Type sizes the content outgrows the screen and must scroll.
/// The probe's `containerRelativeFrame` already excludes the scroller's insets.
struct CentredInScroller: ViewModifier {
    let isCentred: Bool

    @State private var available: CGFloat = 0

    func body(content: Content) -> some View {
        content
            .frame(minHeight: isCentred ? available : 0, alignment: .center)
            .background {
                // A background takes its size from the content and never gives
                // any back, so the probe measures without moving anything.
                Color.clear
                    .containerRelativeFrame(.vertical)
                    .onGeometryChange(for: CGFloat.self) { $0.size.height } action: {
                        available = $0
                    }
            }
    }
}

extension View {
    /// Centres this view in the height its scroller offers. See
    /// [`CentredInScroller`]. `isCentred` lets a scroller ask per screen
    /// without the modifier leaving the view tree, which would reset the
    /// measurement each time it came back.
    func centredInScroller(_ isCentred: Bool = true) -> some View {
        modifier(CentredInScroller(isCentred: isCentred))
    }
}
