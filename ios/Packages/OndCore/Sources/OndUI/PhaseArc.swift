import SwiftUI

/// A phase's progress as a filling arc: a faint track with an arc wound over
/// it from twelve o'clock. The Reduce Motion breath guide on phone and wrist,
/// drawn once so the two devices guide the same breath the same way. Raw
/// scalars in, like `BreathGlyph`: whose fraction and whose tint stay the
/// caller's business.
public struct PhaseArc: View {
    /// How far through the phase, 0...1 — the arc's sweep.
    let fraction: Double
    /// The phase's colour; the track is the same colour at track strength.
    let tint: Color
    /// The stroke of track and arc alike. Heavy where the arc is the whole
    /// guide, lighter where the face is small.
    let lineWidth: CGFloat

    /// Memberwise construction; the fields above say what each scalar means.
    public init(fraction: Double, tint: Color, lineWidth: CGFloat) {
        self.fraction = fraction
        self.tint = tint
        self.lineWidth = lineWidth
    }

    public var body: some View {
        ZStack {
            Circle()
                .stroke(tint.opacity(0.2), lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: fraction)
                .stroke(tint, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
    }
}
