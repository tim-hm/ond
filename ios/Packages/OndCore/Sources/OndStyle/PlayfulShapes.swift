import SwiftUI

// The two shapes the playful register draws a breath with. Here rather than
// beside the view that composes them because the app target has no test
// bundle, and both were tuned by eye — `PlayfulShapeTests` holds the polar
// curve.

/// A round bud that becomes a six-petalled flower. A polar curve rather than
/// six overlaid ovals: one closed path takes one fill and shows no seams.
/// `openness` moves the petal depth only — a tip's radius stays the circle's,
/// so the flower grows into the bounds the sphere occupied.
public struct PetalShape: Shape {
    /// 0 is a circle; 1 puts the valleys at `petalDepth` of the tips.
    public var openness: Double

    public init(openness: Double) {
        self.openness = openness
    }

    /// Six, because it is the count that still reads as a flower at a glance
    /// while leaving each petal wide enough to survive the softening at the rim.
    static let petals = 6

    /// How far the valleys between petals cut in at full openness. Tuned by
    /// rendering: at 0.30 the open flower read as a starfish; 0.22 keeps a
    /// body. No `animatableData`: a `TimelineView(.animation)` hands this a
    /// fresh `openness` every frame, so an interpolator would rebuild the path
    /// twice per frame and leave the petals trailing the breath clock.
    static let petalDepth = 0.22

    public func path(in rect: CGRect) -> Path {
        let centre = CGPoint(x: rect.midX, y: rect.midY)
        let reach = min(rect.width, rect.height) / 2
        let depth = Self.petalDepth * min(max(openness, 0), 1)
        // Enough segments that the curve reads as smooth at 260pt and few enough
        // that rebuilding it every frame stays cheap.
        let segments = 120

        var path = Path()
        for segment in 0 ... segments {
            let angle = Double(segment) / Double(segments) * 2 * .pi
            let radius = reach * (1 - depth + depth * cos(Double(Self.petals) * angle))
            let point = CGPoint(
                x: centre.x + radius * cos(angle),
                y: centre.y + radius * sin(angle)
            )

            if segment == 0 {
                path.move(to: point)
            } else {
                path.addLine(to: point)
            }
        }
        path.closeSubpath()

        return path
    }
}

/// A teardrop with a pointed tip and a round foot — a flame as a child draws
/// one, which is the register this whole screen is in.
public struct FlameShape: Shape {
    public init() {}

    public func path(in rect: CGRect) -> Path {
        let width = rect.width
        let height = rect.height
        var path = Path()

        path.move(to: CGPoint(x: rect.midX, y: rect.minY))
        path.addCurve(
            to: CGPoint(x: rect.maxX, y: rect.minY + height * 0.62),
            control1: CGPoint(x: rect.midX + width * 0.30, y: rect.minY + height * 0.20),
            control2: CGPoint(x: rect.maxX, y: rect.minY + height * 0.38)
        )
        path.addCurve(
            to: CGPoint(x: rect.midX, y: rect.maxY),
            control1: CGPoint(x: rect.maxX, y: rect.maxY - height * 0.06),
            control2: CGPoint(x: rect.midX + width * 0.26, y: rect.maxY)
        )
        path.addCurve(
            to: CGPoint(x: rect.minX, y: rect.minY + height * 0.62),
            control1: CGPoint(x: rect.midX - width * 0.26, y: rect.maxY),
            control2: CGPoint(x: rect.minX, y: rect.maxY - height * 0.06)
        )
        path.addCurve(
            to: CGPoint(x: rect.midX, y: rect.minY),
            control1: CGPoint(x: rect.minX, y: rect.minY + height * 0.38),
            control2: CGPoint(x: rect.midX - width * 0.30, y: rect.minY + height * 0.20)
        )
        path.closeSubpath()

        return path
    }
}
