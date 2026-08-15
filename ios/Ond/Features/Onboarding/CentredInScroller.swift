import SwiftUI

/// Stretches scroll content to the height its scroller actually offers, so that
/// what is in it sits in the middle of the screen rather than hugging the
/// toolbar above a screenful of nothing.
///
/// For the greeting that opens first run, which is the one screen there with
/// nothing to work down. Every other step — the questions and the terms alike —
/// reads from the top and leaves this alone.
///
/// A `minHeight` rather than a fixed height, which is the whole reason this is
/// not `containerRelativeFrame` used directly: at the largest Dynamic Type sizes
/// the content outgrows the screen and has to scroll, and a fixed height
/// truncates it instead.
///
/// The height comes from a probe rather than from measuring the scroller and
/// subtracting what its insets take: `containerRelativeFrame` resolves against
/// the scroller's own content area, which is already the frame minus the inset
/// the button sits in. One measurement to get right instead of two.
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
    /// [`CentredInScroller`].
    ///
    /// - Parameter isCentred: whether to fill at all, so a scroller whose
    ///   content changes between screens can ask per screen without the call
    ///   moving in and out of the view tree — which would reset the measurement
    ///   every time it came back.
    func centredInScroller(_ isCentred: Bool = true) -> some View {
        modifier(CentredInScroller(isCentred: isCentred))
    }
}
