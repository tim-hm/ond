import OndKit
import OndStyle
import OndUI
import SwiftUI

/// The session's heart rate as one line, on the summary that follows it.
///
/// The badge during a session answers "what is my heart doing"; this answers the
/// question the badge cannot, which is whether the last few minutes did
/// anything. It is the person's own sensor saying so — no score, no zone, no
/// colour that changes at a threshold, and no sentence claiming they settled.
/// The line either fell or it did not, and they can see which.
///
/// Both axes are scaled to this session alone, so the two numbers beside it are
/// what stop the shape being read as a magnitude — see `PulseTrace.points()`,
/// which explains why a fixed axis would draw every settling as the same flat
/// line.
///
/// Drawn only where there is enough to draw. Most sessions have no watch on the
/// other end and this is simply absent, which is the same silence every other
/// surface in this feature keeps.
struct PulseCurve: View {
    let trace: PulseTrace

    private static let height: CGFloat = 56

    var body: some View {
        if let range = trace.range, trace.isWorthDrawing {
            VStack(alignment: .leading, spacing: Theme.Spacing.tight) {
                Text("Your heart, through the session")
                    .font(.caption)

                line
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

    /// A stroked path and nothing else — no fill, no grid, no dots on the
    /// readings. A fill reads as a quantity and the readings are samples of a
    /// continuous thing rather than counts of one.
    private var line: some View {
        Canvas { context, size in
            let points = trace.points()
            guard points.count > 1 else { return }

            var path = Path()
            for (index, point) in points.enumerated() {
                // y inverted: the trace counts up from its slowest reading and
                // a view's origin is its top left, so the fastest heart rate
                // belongs at the smallest y.
                let at = CGPoint(
                    x: point.x * size.width,
                    y: (1 - point.y) * size.height
                )
                if index == 0 {
                    path.move(to: at)
                } else {
                    path.addLine(to: at)
                }
            }

            context.stroke(
                path,
                with: .color(Theme.Ink.primary),
                style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round)
            )
        }
        // The canvas draws to its own bounds, so a two-point stroke would sit
        // half outside them at the extremes.
        .padding(.vertical, 1)
    }
}
