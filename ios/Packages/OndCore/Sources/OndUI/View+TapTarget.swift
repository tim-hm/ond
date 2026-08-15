#if os(iOS)
    import SwiftUI

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
        /// really is, and a Dynamic Type setting that needs more than
        /// `Theme.Metrics.minimumTapTarget` gets it.
        ///
        /// Height only. A control that also wants the width offered to it says
        /// so itself with a `frame(maxWidth:)` in front of this — one caller
        /// does, and a parameter here would be read by every caller that does
        /// not.
        ///
        /// iOS only. Phone controls generally grow in height without taking a
        /// fixed width. Watch icon controls use `Theme.Metrics.minimumTapTarget`
        /// directly so their visual shape can remain smaller than their square
        /// hit area.
        func tapTarget() -> some View {
            frame(minHeight: Theme.Metrics.minimumTapTarget)
                .contentShape(Rectangle())
        }
    }
#endif
