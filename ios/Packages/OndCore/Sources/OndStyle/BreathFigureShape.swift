import SwiftUI

/// A `BreathFigure.Pose` as one path. A single `Shape` because a Live Activity
/// can draw one stroked path where `Canvas` cannot run — the system archives a
/// widget's view tree rather than running its draw closures. One path carries
/// only one stroke, which is why a nostril is spent on where the outline goes
/// rather than on per-place stroke weights.
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
