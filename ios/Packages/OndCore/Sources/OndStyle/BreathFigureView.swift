import SwiftUI

/// The breath figure, drawn.
///
/// A view in `OndStyle`, which is the one thing in this target that is not a
/// mapping — and the exception is the design rather than a leak. Views stay
/// per-app because a wrist is not a small phone and the two want different
/// *layouts*; this is not a layout. It is one drawing that has to be the same
/// drawing at 260 points on a phone, at 90 on a wrist, and at 22 in the Dynamic
/// Island, and three copies of it would be three figures that agree right up
/// until somebody edits one.
///
/// It holds no state, reads no environment, and carries no `animation` modifier.
/// Motion arrives entirely as a new `Pose` from whatever is driving the clock,
/// so a figure nobody is breathing to is one path that is never rebuilt — and
/// the caller decides whether a clock runs at all, rather than this view keeping
/// one alive to redraw something that is not moving.
///
/// `size` is a parameter rather than a `GeometryReader` read because the stroke
/// weight depends on it: a figure has to know how big it is before it can decide
/// how heavily to draw, and every caller already knows.
///
/// `stroke` is a resolved colour rather than a phase, which is what keeps this
/// view free of the domain. `TechniqueFigure.Ink(_:).colour(on:)` is the one line
/// that turns a phase into it.
public struct BreathFigureView: View {
    public let pose: BreathFigure.Pose
    public let stroke: Color
    /// The figure's extent in points, on both axes.
    public let size: CGFloat

    public init(pose: BreathFigure.Pose, stroke: Color, size: CGFloat) {
        self.pose = pose
        self.stroke = stroke
        self.size = size
    }

    public var body: some View {
        BreathFigureShape(pose: pose)
            .stroke(
                stroke,
                style: StrokeStyle(lineWidth: BreathFigure.lineWidth(across: size), lineCap: .round)
            )
            .frame(width: size, height: size)
    }
}
