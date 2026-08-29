import SwiftUI

/// The whole session as an arc, filling clockwise from twelve. Drawn once so
/// the phone's orb and the wrist's face cannot wind the same fact two ways.
/// No track under it: the ring it rides is the track.
public struct SessionArc: View {
    /// How far through the session, 0...1 — the arc's sweep.
    let fraction: Double

    /// Memberwise construction; the field above says what the scalar means.
    public init(fraction: Double) {
        self.fraction = fraction
    }

    /// Heavy enough to read over the hairline it rides, and round-capped so a
    /// session a few seconds old still shows something.
    private static let stroke = StrokeStyle(lineWidth: 3, lineCap: .round)

    public var body: some View {
        Circle()
            .trim(from: 0, to: fraction)
            .stroke(Theme.Breath.inhale, style: Self.stroke)
            .rotationEffect(.degrees(-90))
    }
}
