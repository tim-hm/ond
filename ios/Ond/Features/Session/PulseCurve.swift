import OndKit
import OndUI
import SwiftUI

/// The session's heart rate as one line, on the summary that follows it. No
/// score, no zone, no sentence claiming they settled: the line either fell or
/// it did not. Both axes scale to this session alone — `PulseTrace.points()`
/// says why a fixed axis flattens every settling. It owns its environment read,
/// like `PulseBadge` and for its reason; absent when there is too little to draw.
struct PulseCurve: View {
    @Environment(PulseMonitor.self) private var pulse

    private static let lineWidth: CGFloat = 2
    private static let height: CGFloat = 56

    var body: some View {
        let trace = pulse.trace

        if let range = trace.range, trace.isWorthDrawing {
            // The figures sit above and below the line because they label the
            // vertical axis. Beside each other under a time axis they read as
            // a start and an end — exactly backwards for a settling, with the
            // smaller number under a line that begins at the top.
            VStack(alignment: .leading, spacing: Theme.Spacing.tight) {
                Text("Your heart, while your watch was sharing")
                    .font(.caption)

                Text("\(range.upperBound) bpm")
                    .font(.caption)
                    .monospacedDigit()

                // A stroked line and nothing else — no fill, no grid, no dots on
                // the readings. A fill reads as a quantity, and the readings are
                // samples of a continuous thing rather than counts of one.
                PulseCurveShape(runs: trace.runs(), lineWidth: Self.lineWidth)
                    .stroke(
                        Theme.Ink.primary,
                        style: StrokeStyle(
                            lineWidth: Self.lineWidth,
                            lineCap: .round,
                            lineJoin: .round
                        )
                    )
                    .frame(height: Self.height)

                Text("\(range.lowerBound)")
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

/// The trace's unit-space points stretched across whatever frame they are
/// given. A `Shape` rather than a `Canvas` — `BreathFigureShape` records why.
/// Stretched rather than scaled uniformly, unlike `TechniqueFigure`'s
/// renderers: a heart rate has no aspect ratio to preserve, and a curve that
/// kept one would leave the frame half empty.
private struct PulseCurveShape: Shape {
    /// One entry per unbroken run of readings — see `PulseTrace.runs()`, which
    /// explains why a trace is not always one line.
    let runs: [[CGPoint]]
    let lineWidth: CGFloat

    func path(in rect: CGRect) -> Path {
        // Inset by half the stroke, the rule `TechniqueFigure.transform` states:
        // a path drawn to the bounds is stroked half outside them, so the first
        // and last readings would be clipped lengthwise and the extremes of the
        // line flattened against the top and bottom edges.
        let inside = rect.insetBy(dx: lineWidth / 2, dy: lineWidth / 2)
        // `insetBy` answers a null rect when the inset exceeds the rect, and
        // every point derived from one is infinite. The same guard
        // `TechniqueFigure.transform` keeps, and for the same reason: a frame
        // this small is a layout still settling, not a drawing to attempt.
        guard inside.width > 0, inside.height > 0 else { return Path() }

        var path = Path()
        for run in runs {
            path.addLines(run.map { point in
                CGPoint(
                    x: inside.minX + point.x * inside.width,
                    // Inverted: the trace counts up from its slowest reading and
                    // a view's origin is its top left, so the fastest heart rate
                    // belongs at the smallest y.
                    y: inside.minY + (1 - point.y) * inside.height
                )
            })
        }
        return path
    }
}
