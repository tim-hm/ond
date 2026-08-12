import OndKit
import OndUI
import SwiftUI

/// The session's heart rate as one line, on the summary that follows it.
///
/// The badge during a session answers "what is my heart doing"; this answers the
/// question the badge cannot, which is whether the last few minutes did
/// anything. It is the person's own sensor saying it — no score, no zone, no
/// colour that changes at a threshold, and no sentence claiming they settled.
/// The line either fell or it did not, and they can see which.
///
/// Both axes are scaled to this session alone, so the two numbers beside it are
/// what stop the shape being read as a magnitude — see `PulseTrace.points()`,
/// which explains why a fixed axis would draw every settling as the same flat
/// line.
///
/// Owns its environment read, like `PulseBadge` and for its reason: a reading
/// that arrived while this was on screen would otherwise invalidate the whole
/// summary — the headline, the stats, the mood row and the Done button — rather
/// than the one view that cares. Nothing does arrive by then, because a finished
/// session has already ended the arrangement; owning the read is what keeps that
/// a fact about the sequence rather than something this view depends on.
///
/// Drawn only where there is enough to draw. Most sessions have no watch on the
/// other end and this is simply absent, which is the same silence every other
/// surface in this feature keeps.
struct PulseCurve: View {
    @Environment(PulseMonitor.self) private var pulse

    private static let lineWidth: CGFloat = 2
    private static let height: CGFloat = 56

    var body: some View {
        let trace = pulse.trace

        if let range = trace.range, trace.isWorthDrawing {
            VStack(alignment: .leading, spacing: Theme.Spacing.tight) {
                Text("Your heart, through the session")
                    .font(.caption)

                // A stroked line and nothing else — no fill, no grid, no dots on
                // the readings. A fill reads as a quantity, and the readings are
                // samples of a continuous thing rather than counts of one.
                PulseCurveShape(points: trace.points(), lineWidth: Self.lineWidth)
                    .stroke(
                        Theme.Ink.primary,
                        style: StrokeStyle(
                            lineWidth: Self.lineWidth,
                            lineCap: .round,
                            lineJoin: .round
                        )
                    )
                    .frame(height: Self.height)

                HStack {
                    Text("\(range.lowerBound)")
                    Spacer()
                    Text("\(range.upperBound) bpm")
                }
                .font(.caption)
                .monospacedDigit()
            }
            .foregroundStyle(Theme.Ink.primary)
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Heart rate through the session")
            .accessibilityValue(
                "Between \(range.lowerBound) and \(range.upperBound) beats per minute"
            )
        }
    }
}

/// The trace's unit-space points stretched across whatever frame they are given.
///
/// A `Shape` rather than a `Canvas`, which is the package's settled answer for
/// drawing a variable number of runs — `BreathFigureShape` records why, and the
/// short version is that a draw closure is not a view tree. Stretched rather
/// than scaled uniformly, unlike `TechniqueFigure`'s renderers: a heart rate has
/// no aspect ratio to preserve, and a curve that kept one would leave the frame
/// half empty.
private struct PulseCurveShape: Shape {
    let points: [CGPoint]
    let lineWidth: CGFloat

    func path(in rect: CGRect) -> Path {
        // Inset by half the stroke, the rule `TechniqueFigure.transform` states:
        // a path drawn to the bounds is stroked half outside them, so the first
        // and last readings would be clipped lengthwise and the extremes of the
        // line flattened against the top and bottom edges.
        let inside = rect.insetBy(dx: lineWidth / 2, dy: lineWidth / 2)

        var path = Path()
        path.addLines(points.map { point in
            CGPoint(
                x: inside.minX + point.x * inside.width,
                // Inverted: the trace counts up from its slowest reading and a
                // view's origin is its top left, so the fastest heart rate
                // belongs at the smallest y.
                y: inside.minY + (1 - point.y) * inside.height
            )
        })
        return path
    }
}
