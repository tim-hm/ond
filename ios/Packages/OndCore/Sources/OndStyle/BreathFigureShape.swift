import SwiftUI

/// A `BreathFigure.Pose` as one path.
///
/// One `Shape` holding the whole figure rather than a stack of views, for two
/// reasons the prototype is measured against. The figure is one view, so a pose
/// that has not changed costs nothing at all; and a single path stroked once is
/// drawable by a Live Activity, where `Canvas` — the obvious way to draw a
/// variable number of shapes — is not available, because the system archives a
/// widget's view tree rather than running its draw closures.
///
/// That is also why a nostril is spent on where the outline goes and where it
/// stops rather than on per-place stroke weights: one path can carry a different
/// corner for every place, but only one stroke for all of them.
///
/// The pose is placed as each point is added rather than by transforming a
/// finished path, matching `FigureShape` and for the same reason — this runs on
/// every layout pass of every visible figure.
public struct BreathFigureShape: Shape {
    public let pose: BreathFigure.Pose

    public init(pose: BreathFigure.Pose) {
        self.pose = pose
    }

    public func path(in rect: CGRect) -> Path {
        // The unit square is square; a non-square rect gets the inscribed one
        // rather than an oval breath.
        let extent = min(rect.width, rect.height)
        let middle = CGPoint(x: rect.midX, y: rect.midY)
        let outline = pose.outline
        var path = Path()

        guard let first = outline.points.first else { return path }

        path.move(to: place(first, at: middle, across: extent))
        for point in outline.points.dropFirst() {
            path.addLine(to: place(point, at: middle, across: extent))
        }
        if outline.isClosed {
            path.closeSubpath()
        }

        return path
    }

    private func place(_ point: CGPoint, at middle: CGPoint, across extent: CGFloat) -> CGPoint {
        CGPoint(x: middle.x + point.x * extent, y: middle.y + point.y * extent)
    }
}
