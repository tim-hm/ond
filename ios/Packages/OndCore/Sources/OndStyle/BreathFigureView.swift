import SwiftUI

/// The breath figure, drawn — the one view in `OndStyle`, an exception by
/// design: the same drawing must serve 260pt on a phone, 90pt on a wrist and
/// 22pt in the Island, so it cannot be three per-app copies. No state and no
/// `animation` modifier — motion arrives as a new `Pose`, and the caller owns
/// the clock. `TechniqueFigure.Ink(_:).colour(on:)` turns a phase into `stroke`.
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
