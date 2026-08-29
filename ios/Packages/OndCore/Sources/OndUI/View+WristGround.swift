#if os(watchOS)
    import SwiftUI

    public extension View {
        /// Grounds a wrist screen in an accent — the watch's answer to
        /// `accentGround(_:)`. The system draws the wash itself through
        /// `containerBackground(for: .navigation)`, reaching under the time and
        /// the chrome where a plain background stops. The strength stays a
        /// literal: `Theme.Wash`'s values carry a contrast guarantee this screen does not make.
        func wristGround(_ accent: Color) -> some View {
            containerBackground(accent.gradient.opacity(0.3), for: .navigation)
        }
    }
#endif
