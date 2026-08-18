import CoreGraphics
import Foundation
import OndKit

/// One technique as the page's wide plot: a single cycle drawn across the
/// column, between the empty-lungs baseline and the full-lungs ceiling.
///
/// The same geometry as `SVG.figure`, at a size that can afford to say more.
/// The small figure states a shape; this one states a shape against its
/// references, so the height of a rise and the length of a plateau are readable
/// as quantities rather than as a silhouette. Both come out of
/// `TechniqueFigure`, and both place it with `transform(fitting:into:)` — the
/// rule that must not be copied.
///
/// A second marker vocabulary rather than a mode switch on the command line.
/// One run over the page redraws every generated figure whatever kind it is,
/// which keeps `generate:diagrams` and `check:diagrams` as one pass each; a
/// mode would mean two invocations that could disagree about which was last
/// run.
enum Plot {
    /// How wide the plot draws. A page decision — the column it spans — and the
    /// only dimension stated here.
    ///
    /// **The height is not a second decision.** `TechniqueFigure.transform` is
    /// uniform on purpose: the ratio between a rise and a fall is the thing the
    /// drawing states, and stretching to fill a chosen rectangle would warp
    /// every slope against every other. So the box takes its height from the
    /// figure's own aspect, and the drawing fills the width it was given. A
    /// height picked independently either letterboxes the cycle into the middle
    /// of an empty band or has to warp it to fit, and the first is what a
    /// stated 150 produced: a 178-point drawing centred in 560 points of air.
    static let width = 560.0

    /// Room for the labels and the boundary dots, which sit outside the line.
    /// Wider than it is tall for the small figure's reason — a label centred
    /// near the left or right edge overhangs by half its width.
    static let margin = CGSize(width: 34, height: 26)

    /// The gap between a staged protocol's stages.
    static let gap = 18.0

    /// The weight the cycle is drawn at. Heavier than the small figure's 1.5,
    /// because a line that reads at 220 points wide is a thread at 560.
    static let lineWidth = 2.5

    /// Holds are drawn a second time, heavier, on top of the cycle.
    ///
    /// A plateau is the one part of a breath somebody is asked to *do nothing*
    /// through, and at this width it is also the part with the least ink — a
    /// four-second hold is a short flat run beside a four-second rise's long
    /// diagonal. Overdrawing puts the emphasis back where the duration says it
    /// belongs.
    ///
    /// Here rather than in `Stroke.weight(on:)`, deliberately. That rule is
    /// shared by four renderers, and a hold that thickened everywhere would
    /// change the phone's chart and the watch's glyph to serve a decision the
    /// marketing page made about one drawing.
    static let holdWidth = 4.0

    /// The radius of the dot on each corner of the waveform.
    static let boundaryRadius = 3.0

    /// Where one technique's generated plot sits in the page — the same marker
    /// arrangement as a figure's, under its own name so the two cannot be
    /// mistaken for each other.
    static let vocabulary = Markers.Vocabulary(kind: "plot")

    static func svg(for technique: Technique) -> String {
        let figures = TechniqueFigure.all(for: technique)
        let box = box(for: figures)
        let content = SVG.content(of: box, inside: margin)
        var body: [String] = []

        for (index, figure) in figures.enumerated() {
            let cell = SVG.cell(index: index, of: figures.count, in: content, gap: gap)
            let transform = TechniqueFigure.transform(
                fitting: figure.boundsIncludingCeiling,
                into: cell,
                lineWidth: lineWidth
            )

            body.append(SVG.path(figure.ceiling, through: transform, at: lineWidth))
            // A plateau at its own weight in the same pass, rather than the
            // cycle drawn once and the holds again over it. A heavier stroke
            // with the same caps covers the thinner one exactly, so the second
            // pass was two elements saying what one says.
            body += figure.drawable.map {
                SVG.path($0, through: transform, at: $0.ink == .hold ? holdWidth : lineWidth)
            }
            body += figure.boundaries.map { dot($0, through: transform) }
            body += figure.labels.map { SVG.text($0, through: transform) }
        }

        return SVG.document(box: box, label: figures.spoken, body: body)
    }

    /// The width the plot spans, and the height that width implies.
    ///
    /// The tallest stage decides, so a staged protocol's stages sit on one
    /// baseline at one scale rather than each filling its own cell — a Wim Hof
    /// round's retention is not a taller breath than its recovery hold, and
    /// scaling them apart would say it was.
    static func box(for figures: [TechniqueFigure]) -> CGSize {
        let cell = SVG.cellWidth(
            of: figures.count,
            across: width - margin.width * 2,
            gap: gap
        )
        let tallest = figures
            .map(\.boundsIncludingCeiling)
            .map { $0.width > 0 ? $0.height / $0.width : 0 }
            .max() ?? 0

        return CGSize(width: width, height: (cell * tallest).rounded() + margin.height * 2)
    }

    static func dot(_ point: CGPoint, through transform: CGAffineTransform) -> String {
        let placed = point.applying(transform)
        return """
        <circle cx="\(SVG.number(placed.x))" cy="\(SVG.number(placed.y))" \
        r="\(SVG.number(boundaryRadius))" class="plot-boundary" />
        """
    }
}
