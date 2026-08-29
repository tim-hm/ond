import SwiftUI

public extension View {
    /// A numeral drawn at a display size, scaled with Dynamic Type but bounded.
    /// A text style cannot express these — `.largeTitle` stops at 34pt — and a
    /// fixed `.system(size:)` does not scale for the person who most needs the
    /// number large. A `ScaledMetric` grows `size`, capped at 1.4× so the digit
    /// keeps room around it. Always monospaced: a live numeral must not shuffle sideways.
    func displayNumeral(size: CGFloat, design: Font.Design = .default) -> some View {
        modifier(DisplayNumeral(base: size, design: design))
    }
}

/// The scaling half of `displayNumeral(size:design:)`, a `ViewModifier` because
/// `ScaledMetric` reads the environment and so has to live on something SwiftUI
/// instantiates.
private struct DisplayNumeral: ViewModifier {
    let base: CGFloat
    let design: Font.Design

    /// `base` grown by the reader's Dynamic Type setting. Built in `init`
    /// rather than declared with one, because the base is the caller's and a
    /// property wrapper cannot take it from a stored property.
    @ScaledMetric private var scaled: CGFloat

    /// How much larger than its base a numeral is ever drawn. Roughly the jump
    /// from the default setting to the largest non-accessibility one, which is
    /// where the growth stops being legibility and starts being a digit with
    /// the screen to itself.
    private static let mostGrowth: CGFloat = 1.4

    init(base: CGFloat, design: Font.Design) {
        self.base = base
        self.design = design
        // Against `.largeTitle`, the style these numerals are the next step up
        // from, so they grow on the same curve as the copy beside them rather
        // than on body text's, which accelerates harder.
        _scaled = ScaledMetric(wrappedValue: base, relativeTo: .largeTitle)
    }

    func body(content: Content) -> some View {
        content
            .font(.system(size: min(scaled, base * Self.mostGrowth), design: design)
                .weight(.light)
                .monospacedDigit())
            // A display numeral that wrapped would be a broken screen rather
            // than a wide one, and the cap above is a design bound rather than
            // a fit guarantee — a long value on a narrow phone at the largest
            // setting shrinks to stay on one line.
            .lineLimit(1)
            .minimumScaleFactor(0.5)
    }
}
