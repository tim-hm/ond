#if os(iOS)
    import SwiftUI

    public extension View {
        /// Grows a control to the minimum touch target and makes the whole of
        /// it tappable — both halves, always: a frame alone leaves the hit
        /// area on the glyph inside it, the version of this that looks fixed
        /// and is not. A minimum, so Dynamic Type can take more; height only —
        /// a caller that wants the width says so with its own `frame(maxWidth:)`.
        func tapTarget() -> some View {
            frame(minHeight: Theme.Metrics.minimumTapTarget)
                .contentShape(Rectangle())
        }
    }
#endif
