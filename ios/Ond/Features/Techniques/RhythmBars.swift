import OndKit
import OndStyle
import OndUI
import SwiftUI

/// One cycle of an exercise as bars, to scale, at the size a list row can
/// carry. The same numbers as the chart and the marketing site — three
/// projections of `BreathRhythm`. The slope is dropped on purpose; the widths
/// survive. Colours come from `TechniqueFigure.Ink`, which keeps the caption's
/// promise that holds are indigo wherever they appear. Only the list draws it.
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

    /// What the exercise is for, which is what its phases are coloured against
    /// — the same accent its own figure is drawn in.
    let goal: TechniqueGoal

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
                    .fill(TechniqueFigure.Ink(segment.kind).colour(on: goal.accent))
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
}
