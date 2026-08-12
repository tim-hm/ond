#if os(iOS)
    import SwiftUI

    /// The Human Interface Guidelines' minimum touch target. A control smaller
    /// than this is one somebody has to aim at.
    private let minimumTapTarget: CGFloat = 44

    public extension View {
        /// Grows a control to the minimum touch target and makes the whole of
        /// it tappable.
        ///
        /// Both halves, always, which is the reason this exists rather than a
        /// frame at each site. A frame alone moves the layout and leaves the
        /// hit area on the glyph inside it, so a `.footnote` button reads as a
        /// 44pt row and still only answers to a tap on its sixteen points of
        /// text — the version of this that looks fixed and is not.
        ///
        /// A minimum rather than a size: the text decides how tall the control
        /// really is, and a Dynamic Type setting that needs more than 44 points
        /// gets it.
        ///
        /// iOS only. The number is the phone's guideline, and the watch — where
        /// the whole screen is a target and the crown is the other way in — has
        /// no use for it.
        ///
        /// - Parameter spanningWidth: whether the target should also take the
        ///   full width offered. For a control in a row of them, where the gaps
        ///   between the glyphs are dead space with nowhere else to go.
        func tapTarget(spanningWidth: Bool = false) -> some View {
            frame(
                maxWidth: spanningWidth ? .infinity : nil,
                minHeight: minimumTapTarget
            )
            .contentShape(Rectangle())
        }
    }
#endif
