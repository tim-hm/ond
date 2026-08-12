#if os(watchOS)
    import SwiftUI

    public extension View {
        /// Grounds a wrist screen in an accent — the watch's answer to
        /// `accentGround(_:)`.
        ///
        /// Two things differ from the phone's, and both are watchOS's doing. The
        /// system draws the wash itself, through `containerBackground(for:
        /// .navigation)`, so it reaches under the time and the navigation chrome
        /// where a plain background would stop at the content. And it takes the
        /// gradient rather than a pair of stops, because the platform is already
        /// fading it towards the bottom of the display.
        ///
        /// A modifier rather than the one line it wraps because that line was in
        /// three screens with the same magic strength written out each time —
        /// which is the point at which this repo's DRY rule says to name the
        /// thing. The strength is what it always was, kept as a literal here
        /// rather than promoted to `Theme.Wash`: those two values are the phone
        /// gradient's ends and are measured against a contrast guarantee this
        /// screen does not make.
        ///
        /// - Parameter accent: The colour to wash the ground in — a goal's
        ///   accent on a session, the brand's on a screen that belongs to no
        ///   technique.
        func wristGround(_ accent: Color) -> some View {
            containerBackground(accent.gradient.opacity(0.3), for: .navigation)
        }
    }
#endif
