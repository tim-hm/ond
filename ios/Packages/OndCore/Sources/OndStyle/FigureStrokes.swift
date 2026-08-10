import OndKit
import OndUI
import SwiftUI

/// A technique figure's strokes, drawn: every pen of `figure.drawable` as a
/// `FigureShape`, coloured and weighted the one way an önd figure is.
///
/// In `OndStyle` for the same reason `FigureShape` is: the phone's chart and
/// the watch's glyph reduced to this exact body once the figures collapsed to
/// one construction, and per-target copies of "which stroke gets which colour,
/// weight, cap and dash" are the drift `mise run check:diagrams` structurally
/// cannot catch — it only pins the SVG generator's copy. What stays per surface
/// is everything around this: size, frame, labels, and accessibility.
public struct FigureStrokes: View {
    public let figure: TechniqueFigure
    /// The goal accent the inks resolve against.
    public let accent: Color
    public let lineWidth: CGFloat
    /// Whether an open-ended stage's strokes draw dashed at this size. The
    /// chart dashes; the watch does not — a 4pt dash at glyph size is a line
    /// with holes in it, and a carousel page makes no promise about duration
    /// for the dash to qualify.
    public let dashed: Bool

    public init(figure: TechniqueFigure, accent: Color, lineWidth: CGFloat, dashed: Bool) {
        self.figure = figure
        self.accent = accent
        self.lineWidth = lineWidth
        self.dashed = dashed
    }

    public var body: some View {
        ZStack {
            ForEach(Array(figure.drawable.enumerated()), id: \.offset) { _, stroke in
                FigureShape(
                    commands: stroke.commands,
                    bounds: figure.bounds,
                    lineWidth: lineWidth
                )
                .stroke(
                    stroke.ink.colour(on: accent),
                    style: StrokeStyle(
                        lineWidth: stroke.weight(on: lineWidth),
                        lineCap: .round,
                        lineJoin: .round,
                        dash: dashed && stroke.dashed ? TechniqueFigure.Stroke.dash : []
                    )
                )
            }
        }
    }
}
