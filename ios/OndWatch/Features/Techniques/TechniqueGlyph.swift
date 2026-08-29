import OndKit
import OndStyle
import OndUI
import SwiftUI

/// A technique's identity, filling the top of its carousel page: its own
/// figure, drawn from the same `TechniqueFigure` the marketing site is
/// generated from, in the goal's accent. Undecorated on purpose: the figure
/// offers labels and the phone writes them on, but `in · 4` at wrist size is
/// a smudge, and the page beneath already carries the counts as text.
struct TechniqueGlyph: View {
    let technique: Technique
    /// Heavier than the phone's row weight: this drawing carries a whole watch
    /// page, where the phone's carries a list row.
    var lineWidth: CGFloat = 2.5

    var body: some View {
        let accent = technique.goal.accent
        let figures = TechniqueFigure.all(for: technique)

        HStack(spacing: 2) {
            ForEach(Array(figures.enumerated()), id: \.offset) { _, figure in
                FigureStrokes(
                    figure: figure,
                    accent: accent,
                    lineWidth: lineWidth,
                    dashed: false
                )
            }
        }
        // Decoration. The name and duration beneath carry the facts, and a shape
        // is not something VoiceOver can usefully describe.
        .accessibilityHidden(true)
    }
}
