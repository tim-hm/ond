import OndKit
import OndStyle
import OndUI
import SwiftUI

/// One cycle of an exercise as bars, to scale: how long each phase runs,
/// side by side, at the size a list row can carry.
///
/// The same numbers as the chart on the exercise's own screen and the figure on
/// the marketing site — `BreathRhythm` is the one geometry source, and these are
/// three projections of it. What is dropped here is the *slope*: a row is 22
/// points tall and a rise drawn across 12 of them is a diagonal, not a pace. The
/// widths survive, which is the fact worth carrying at this size — that 4-7-8
/// spends most of its cycle breathing out, and that box breathing does not.
///
/// Holds take `Breath.hold` wherever they appear, which is the promise the
/// caption under the list makes and the same one the session's hold ring keeps.
///
/// Feature-local: the Exercises list draws it and nothing else does. The
/// detail screen keeps `BreathRhythmChart`, which has room for the slope.
struct RhythmBars: View {
    /// The cycle to draw, or nil where drawing one would misrepresent the
    /// exercise. A staged protocol is a sequence of different cycles, and one
    /// of them at 56 points wide would state a rhythm the session does not
    /// keep — those rows say "3 rounds · 4 stages" in words instead, and the
    /// detail screen draws every stage at a size that can label them.
    static func cycle(of technique: Technique) -> Stage? {
        technique.isStaged ? nil : technique.stages.first
    }

    let stage: Stage

    /// The spec's own size. Wide enough for the sigh's short sip to survive
    /// `BreathRhythm`'s 8% floor as a visible bar, short enough to sit inside a
    /// row's height without setting it.
    private static let size = CGSize(width: 56, height: 22)

    /// The gap between two bars, in points, taken out of each bar's width
    /// rather than added around them — the whole figure has to stay 56 wide
    /// however many phases the stage holds.
    private static let gap: CGFloat = 2

    var body: some View {
        let rhythm = BreathRhythm(stage: stage)

        HStack(spacing: Self.gap) {
            ForEach(Array(rhythm.segments.enumerated()), id: \.offset) { _, segment in
                RoundedRectangle(cornerRadius: Theme.Radius.mark)
                    .fill(Self.ink(for: segment.kind))
                    .frame(width: max(0, width(of: segment) - Self.gap))
            }
        }
        .frame(width: Self.size.width, height: Self.size.height)
        // Decoration: the row already states the same shape in words — "2 in ·
        // 1 in · 7 out · 5 min" — and a bar chart read aloud phase by phase
        // would be that sentence again, worse.
        .accessibilityHidden(true)
    }

    private func width(of segment: BreathRhythm.Segment) -> CGFloat {
        Self.size.width * (segment.end - segment.start)
    }

    /// The phase colours, from the breath's own language rather than the goal's:
    /// what a bar says is which part of the breath it is, and that means the
    /// same thing on every exercise in the list.
    ///
    /// **Both** holds are indigo, including the rest at the bottom of a box —
    /// which is a hold with empty lungs, and is drawn as one by the exercise's
    /// own figure (`TechniqueFigure.Ink.hold`), by the session's hold ring, and
    /// by the site. The caption under this list promises holds are indigo
    /// wherever they appear, and a rest bar in vapour would be the one place
    /// that sentence was untrue.
    private static func ink(for kind: PhaseKind) -> Color {
        switch kind {
        case .inhale: Theme.Breath.inhale
        case .holdIn, .holdOut: Theme.Breath.hold
        case .exhale: Theme.Breath.exhale.opacity(0.35)
        }
    }
}
