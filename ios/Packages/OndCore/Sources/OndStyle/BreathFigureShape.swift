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
/// That is also why the arrangement's asymmetries are radii and offsets rather
/// than per-place stroke weights: one path can carry a different circle for every
/// place, but only one stroke for all of them.
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
        var path = Path()

        switch pose.configuration.form {
        case .aperture: addAperture(to: &path, at: middle, across: extent)
        case .wheel: addWheel(to: &path, at: middle, across: extent)
        case .rings: addRings(to: &path, at: middle, across: extent)
        }

        return path
    }

    /// The iris, as one closed outline through the arrangement's places.
    ///
    /// Two places make a line rather than an opening, so anything under three
    /// falls back to the rim — which is what a stilled figure draws anyway, and
    /// is the honest shape of an arrangement with no corners.
    private func addAperture(to path: inout Path, at middle: CGPoint, across extent: CGFloat) {
        let corners = pose.vertices.map { place($0, at: middle, across: extent) }
        guard corners.count >= 3, let first = corners.first else {
            return addRim(to: &path, at: middle, across: extent)
        }

        path.move(to: first)
        for corner in corners.dropFirst() {
            path.addLine(to: corner)
        }
        path.closeSubpath()
    }

    /// A rim carrying the breath, with a mark at each place carrying the turn.
    ///
    /// The marks run inwards from the rim rather than across it, so the outermost
    /// thing on the figure stays the one circle — which is what keeps a wheel the
    /// same size as an aperture at the same instant.
    private func addWheel(to path: inout Path, at middle: CGPoint, across extent: CGFloat) {
        addRim(to: &path, at: middle, across: extent)

        for vertex in pose.vertices {
            let outer = place(vertex, at: middle, across: extent)
            let inner = place(
                CGPoint(x: vertex.x * Self.markInset, y: vertex.y * Self.markInset),
                at: middle,
                across: extent
            )
            path.move(to: inner)
            path.addLine(to: outer)
        }
    }

    /// How far in from a place a wheel's mark starts, as a fraction of its
    /// distance out. A quarter of the reach is long enough to see the arrangement
    /// turn and short enough that the rim stays the figure.
    private static let markInset: CGFloat = 0.75

    private func addRings(to path: inout Path, at middle: CGPoint, across extent: CGFloat) {
        for ring in pose.rings {
            add(ring, to: &path, at: middle, across: extent)
        }
    }

    private func addRim(to path: inout Path, at middle: CGPoint, across extent: CGFloat) {
        add(pose.rim, to: &path, at: middle, across: extent)
    }

    private func add(
        _ ring: BreathFigure.Ring,
        to path: inout Path,
        at middle: CGPoint,
        across extent: CGFloat
    ) {
        let centre = place(ring.centre, at: middle, across: extent)
        let radius = ring.radius * extent

        path.addEllipse(in: CGRect(
            x: centre.x - radius,
            y: centre.y - radius,
            width: radius * 2,
            height: radius * 2
        ))
    }

    private func place(_ point: CGPoint, at middle: CGPoint, across extent: CGFloat) -> CGPoint {
        CGPoint(x: middle.x + point.x * extent, y: middle.y + point.y * extent)
    }
}
