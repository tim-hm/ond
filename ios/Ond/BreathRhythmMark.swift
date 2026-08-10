import OndKit
import OndStyle
import OndUI
import SwiftUI

/// An exercise's shape at glyph size: the same figure the detail screen draws,
/// reduced to the line and its wash.
///
/// A miniature rather than a second drawing. What it drops — the labels, the
/// repeat counts, the start dot — is everything that needs reading; what it
/// keeps is the silhouette and the two halves of the breath, which are what tell
/// one exercise from another at a glance. That only works because the silhouettes
/// differ: under the grammar `TechniqueFigure` replaced, five of the nine seeded
/// techniques drew the same circle at this size.
///
/// At `ios/Ond/` rather than inside a feature because two now draw it — the
/// Exercises list row it was written for, and home's cards. It earns the tier for
/// the reason the mark is worth having at all: an exercise has to be the same
/// silhouette wherever it appears, or the glyph stops being recognition and
/// becomes decoration.
///
/// Whether it draws the curated exercise or a dialled one is the caller's, and both
/// callers are right. The Exercises row hands it the catalogue entry, because a list
/// is a portrait of what is on offer and somebody's own settings belong on the screen
/// where they were made; home's cards hand it the dialled one, because a card states
/// a length and a rhythm in words right beside the drawing, and a figure describing a
/// different session from the numbers next to it is worse than no figure.
struct BreathRhythmMark: View {
    let technique: Technique

    /// The mark's extent in points, square.
    var side: CGFloat = 38

    /// Scaled with the figure rather than fixed. The weight was measured at 38
    /// points, and holding it there while the drawing shrinks is what turns a
    /// silhouette into a blot.
    private var lineWidth: CGFloat {
        1.6 * side / 38
    }

    var body: some View {
        let accent = technique.goal.accent
        // The opening figure, which for all but the staged protocols is the only
        // one. A strip of four stages inside a 38-point row is a smudge — it says
        // "this one is complicated" and nothing else — where one silhouette is
        // still the recognition this mark exists for. The detail screen draws
        // every stage, which is where a sequence can actually be read.
        let figure = TechniqueFigure.all(for: technique).first

        Group {
            if let figure {
                let bounds = figure.bounds

                ZStack {
                    FigureShape(
                        commands: figure.fill,
                        bounds: bounds,
                        lineWidth: lineWidth
                    )
                    .fill(
                        LinearGradient(
                            colors: [accent.opacity(0.18), accent.opacity(0.03)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )

                    ForEach(Array(strokes(of: figure).enumerated()), id: \.offset) { _, stroke in
                        FigureShape(
                            commands: stroke.commands,
                            bounds: bounds,
                            lineWidth: lineWidth
                        )
                        .stroke(
                            stroke.ink.colour(on: accent),
                            style: StrokeStyle(
                                lineWidth: stroke.weight(on: lineWidth),
                                lineCap: .round,
                                lineJoin: .round
                            )
                        )
                    }
                }
            }
        }
        .frame(width: side, height: side)
        // Undashed even where the chart dashes: a 4pt dash at this size is a
        // line with holes in it rather than a signal, and neither surface that
        // draws this makes a promise about duration for it to qualify.
        //
        // Decoration: every caller states the facts in words beside it, and
        // VoiceOver reads those as one element without this in the way.
        .accessibilityHidden(true)
    }

    /// The figure without its start dot. At this size the dot is a blob on the
    /// line rather than a mark on it, and neither a list nor a board has a
    /// direction to resolve — nobody traces a card.
    private func strokes(of figure: TechniqueFigure) -> [TechniqueFigure.Stroke] {
        figure.drawable.filter { $0.role != .start }
    }
}
