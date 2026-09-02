import SwiftUI

/// The app icon's open ring, drawn to fill the space it is given. The mark
/// only: a watch face supplies its own ground. The numbers below are the
/// icon's, which states them in `Ond/AppIcon.icon/Assets/RingDark.svg`. Nothing
/// checks that the two agree, so a retuned icon has to be carried here by hand.
struct OpenRingMark: Shape {
    /// The ring on the icon's 1024 grid: how far out it sits, how heavy it is,
    /// how much of it is missing, and where that opening centres — clockwise
    /// from three o'clock, which puts it at the lower left.
    private static let radius = 380.0 / 1024
    private static let stroke = 112.0 / 1024
    private static let gap = 60.0
    private static let opening = 135.0

    /// A round cap puts half a stroke past each end of the arc, so the arc has
    /// to stop one whole stroke width short of the opening meant to show.
    private static let capArc = 180 * stroke / (Double.pi * radius)

    func path(in rect: CGRect) -> Path {
        let side = min(rect.width, rect.height)
        let half = Angle(degrees: (Self.gap + Self.capArc) / 2)
        let arc = Path {
            $0.addArc(
                center: CGPoint(x: rect.midX, y: rect.midY),
                radius: side * Self.radius,
                startAngle: .degrees(Self.opening) + half,
                endAngle: .degrees(Self.opening) - half,
                // The long way round. SwiftUI measures with y downwards, so the
                // increasing direction is the one that reads clockwise.
                clockwise: false
            )
        }

        return arc.strokedPath(StrokeStyle(lineWidth: side * Self.stroke, lineCap: .round))
    }
}
