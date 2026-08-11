import OndKit
import OndStyle
import OndUI
import SwiftUI

/// The exercise's shape, drawn from the same dialled values the session will
/// play. Because it reads the dialled exercise it redraws live as the Customise
/// dials move, which is half the point: a lengthened exhale visibly flattens
/// its slope as the dial turns.
///
/// The one figure on the phone. The list rows and home's cards used to draw a
/// miniature and both let it go — at that size every calm exercise's cycle is
/// the same hump — so the chart is where a technique's shape is met, at a size
/// where its labels and stage titles can actually be read. The watch's glyph
/// and the marketing site's figures come from the same `TechniqueFigure`, so
/// the shape is identical everywhere it survives.
struct BreathRhythmChart: View {
    /// The dialled exercise, not the curated one — the chart is a preview of the
    /// session the Begin button starts.
    let technique: Technique

    /// Built once here rather than in `body`: measuring the labels writes
    /// `labelSizes` once per label, and each write re-evaluates `body` — which
    /// was rebuilding every figure and re-joining `spoken` per measurement. A
    /// dial change makes a new view value and recomputes, which is the redraw
    /// the type exists for.
    private let figures: [TechniqueFigure]
    private let spoken: String

    init(technique: Technique) {
        self.technique = technique
        figures = TechniqueFigure.all(for: technique)
        spoken = figures.spoken
    }

    private static let lineWidth: CGFloat = 2.5
    /// A single figure is the thing on the screen and gets the room for it. A
    /// staged exercise draws one figure per line under its own title, smaller
    /// because there are several of them down the screen — but still large
    /// enough to carry the labels, which is what the side-by-side arrangement
    /// this replaced could not do at any size that fitted.
    private static let side: CGFloat = 168
    private static let stagedSide: CGFloat = 120
    /// The floor under a figure's height. A drawing is as tall as its own ink,
    /// so an open-ended retention — one flat line — would otherwise be given a
    /// frame it cannot fill and a label with nowhere to sit.
    private static let minimumHeight: CGFloat = 44
    /// The gutters the labels live in, *outside* the drawing rather than inset
    /// into it — a figure that gave up its height to the words naming it would
    /// be a caption with a diagram attached. A label lies along its own run,
    /// so the height holds a hold's word over the band's edge and the width
    /// only the overhang of a word near the figure's side.
    private static let labelGutter = CGSize(width: 16, height: 24)
    /// The gap between a line and the nearest edge of the label naming it.
    private static let labelGap: CGFloat = 6

    /// Which label of which figure. A staged exercise draws several figures that
    /// each label their own phases, so a key of the label's index alone had
    /// every figure's first label measuring — and placing — as one.
    private struct LabelKey: Hashable {
        let figure: Int
        let label: Int
    }

    /// Each label's measured size, so it can be pushed clear of the figure by
    /// its own half-height rather than by a guess.
    @State private var labelSizes: [LabelKey: CGSize] = [:]

    var body: some View {
        let side = figures.count > 1 ? Self.stagedSide : Self.side

        // One stage per line, titled, rather than side by side. Four figures
        // across the width of a phone left each of them too small to label and
        // read as one crowded diagram of an exercise that is really a sequence
        // of four simple ones.
        VStack(alignment: .leading, spacing: Theme.Spacing.loose) {
            ForEach(Array(figures.enumerated()), id: \.offset) { index, figure in
                VStack(alignment: .leading, spacing: Theme.Spacing.tight) {
                    if figures.count > 1 {
                        Text(figure.stage.title(at: index))
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Theme.Ink.secondary)
                    }

                    drawing(
                        of: figure,
                        index: index,
                        size: Self.size(of: figure, across: side)
                    )
                    .frame(maxWidth: .infinity)
                }
            }
        }
        .frame(maxWidth: .infinity)
        // One element carrying the whole cycle in words. The figure's own labels
        // say it on screen; this is the same sentence for somebody who is not
        // looking at it, and since the phase capsules that used to carry these
        // facts are gone, it is the only place they exist for VoiceOver.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spoken)
    }

    /// The frame a figure draws in: as wide as the row allows, and as tall as the
    /// drawing itself, so a line does not sit in the middle of a square of empty
    /// space it never reaches into.
    private static func size(of figure: TechniqueFigure, across width: CGFloat) -> CGSize {
        let bounds = figure.bounds
        let tall = bounds.width > 0 ? width * bounds.height / bounds.width : width
        return CGSize(width: width, height: min(max(tall, minimumHeight), width))
    }

    private func drawing(
        of figure: TechniqueFigure,
        index: Int,
        size: CGSize
    ) -> some View {
        // The gutters exist only where there are labels to put in them.
        let gutter = figure.labels.isEmpty ? .zero : Self.labelGutter

        return ZStack {
            FigureStrokes(
                figure: figure,
                accent: Theme.Accent.brand,
                lineWidth: Self.lineWidth,
                dashed: true
            )
            .frame(width: size.width, height: size.height)

            labels(of: figure, at: index, size: size, gutter: gutter)
        }
        .frame(width: size.width + gutter.width * 2, height: size.height + gutter.height * 2)
    }

    /// `in · 4` along the run it names — level over a hold, tilted to the slope
    /// of a breath — the marketing site's treatment, and what let the colour
    /// key that used to sit under this chart go. A reader who has to look up a
    /// legend is reading the picture twice.
    ///
    /// Each label is offset perpendicular to its run by half its own measured
    /// height, so its near *edge* clears the line rather than its centre.
    private func labels(
        of figure: TechniqueFigure,
        at figureIndex: Int,
        size: CGSize,
        gutter: CGSize
    ) -> some View {
        // Anchors are computed in the drawing's own frame and then shifted by
        // the gutter, because the drawing sits centred inside this larger one.
        // The transform is uniform, so the label's angle survives it untouched.
        let drawn = CGRect(origin: .zero, size: size)
        let transform = figure.transform(into: drawn, lineWidth: Self.lineWidth)

        return ForEach(Array(figure.labels.enumerated()), id: \.offset) { index, label in
            let key = LabelKey(figure: figureIndex, label: index)
            let anchor = label.at.applying(transform)
            let size = labelSizes[key] ?? .zero
            let clearance = Self.labelGap + size.height / 2
            let side = label.below ? 1.0 : -1.0

            Text(label.text)
                .font(.caption2.weight(.medium))
                .foregroundStyle(Theme.Ink.secondary)
                .fixedSize()
                .onGeometryChange(for: CGSize.self) { $0.size } action: { labelSizes[key] = $0 }
                .rotationEffect(.radians(label.angle))
                .position(
                    // Perpendicular to the run: (-sin, cos) is the run's
                    // normal on the below side, y downwards.
                    x: gutter.width + anchor.x + side * -sin(label.angle) * clearance,
                    y: gutter.height + anchor.y + side * cos(label.angle) * clearance
                )
        }
    }
}
