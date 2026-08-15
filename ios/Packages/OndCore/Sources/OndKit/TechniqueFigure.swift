import CoreGraphics
import Foundation

/// One stage of a technique as a drawing: one cycle as a line — lung fullness
/// over time — with what colour each part takes, what the parts are labelled,
/// and how to say it aloud.
///
/// **One construction draws everything.** An inhale climbs, a hold runs flat,
/// an exhale falls, and slope carries the pace, so box breathing is a plateau
/// between two equal ramps and 4-7-8's long exhale is a visibly gentle fall.
/// This replaced a grammar of two families — closed polygons for stages that
/// hold, lines for stages that don't, plus a signed midline for the nostrils —
/// which drew a handsome square for box breathing but made every figure a
/// different kind of picture to learn. One cycle, read left to right, is a
/// graph anybody has already met, and it generates for an exercise somebody
/// wrote exactly as it does for a seeded one.
///
/// Geometry only, and deliberately no SwiftUI. Four renderers stand on this: the
/// phone's chart and its list row, the watch's carousel glyph, and the generator
/// that redraws the marketing site's figures (`mise run generate:diagrams`). A
/// technique is the same shape in all four because the shape is decided once,
/// here, and each renderer only turns commands into its own kind of path. The
/// small renderers drop the labels and let the shape alone carry the rhythm;
/// only the chart, at reading size, writes the words on.
///
/// Coordinates are a unit box with y downwards. A renderer fits `bounds` rather
/// than the unit box: an open-ended retention is one flat line, and fitting the
/// box instead would centre it in a square of empty space.
public struct TechniqueFigure: Sendable, Equatable {
    /// What a stroke means, named for the moment of breath rather than a colour
    /// — the palette belongs to whichever renderer is drawing.
    public enum Ink: Sendable, Equatable, Hashable {
        /// The lungs filling.
        case inhale
        /// The lungs emptying.
        case exhale
        /// A breath held, in or out.
        case hold
        /// The empty-lungs reference line the curve rises from. Drawn faint,
        /// and never the subject.
        case baseline
    }

    /// One pen instruction. Deliberately the smallest set that draws every
    /// figure — a line for the holds and the baseline, and a cubic for the
    /// S-curve of a breath.
    public enum Command: Sendable, Equatable {
        case move(to: CGPoint)
        case line(to: CGPoint)
        case curve(to: CGPoint, control1: CGPoint, control2: CGPoint)
    }

    public struct Stroke: Sendable, Equatable {
        public let ink: Ink
        public let commands: [Command]
        /// Whether to draw this stroke dashed — an open-ended stage, whose
        /// durations describe a typical pass rather than a scheduled one.
        public let dashed: Bool

        public init(
            _ ink: Ink,
            _ commands: [Command],
            dashed: Bool = false
        ) {
            self.ink = ink
            self.commands = commands
            self.dashed = dashed
        }

        /// How heavily to draw this stroke, relative to a figure's line width.
        ///
        /// A baseline is reference rather than subject, so it is drawn at a
        /// hairline whatever weight the figure carries.
        ///
        /// Here rather than in `OndStyle` because the SVG generator cannot see
        /// that module and was left spelling the rule out a fourth time — and a
        /// renderer holding its own copy of the rule is the one divergence
        /// `mise run check:diagrams` structurally cannot catch, since both sides
        /// regenerate from whatever each happens to believe.
        public func weight(on lineWidth: CGFloat) -> CGFloat {
            ink == .baseline ? 1 : lineWidth
        }

        /// The dash a person-timed phase draws in — on for four, off for five,
        /// in the same units as the line width. Shared with the site for the
        /// reason above: an open-ended retention that dashed differently in the
        /// two places would look like two different exercises.
        public static let dash: [CGFloat] = [4, 5]
    }

    /// A word on the figure — `in · 4`, or `in · 4 L` where the passage is
    /// lettered.
    /// The site labels its figures this way and the app's chart does too; the
    /// watch leaves the words off and lets the shape speak.
    ///
    /// Every label lies along the run it names: a hold's word sits level over
    /// its flat line, and a breath's word tilts to its slope — anchored at the
    /// run's midpoint, pushed clear along the perpendicular. A word floating
    /// level in the corner above a steep climb reads as a caption that missed;
    /// a word on the slope reads as the slope's name.
    public struct Label: Sendable, Equatable {
        public let text: String
        /// The midpoint of the run this label names, in the same unit box as
        /// the strokes.
        public let at: CGPoint
        /// Whether the label sits under its run rather than over it, so a
        /// renderer can push it clear of the line without knowing the geometry
        /// that produced it.
        public let below: Bool
        /// The curve's tangent at `at`, in radians — clockwise, y down — and
        /// zero for a hold. A renderer may use it directly: the fit every
        /// renderer applies is uniform, so angles survive it.
        public let angle: Double

        public init(text: String, at: CGPoint, below: Bool, angle: Double) {
            self.text = text
            self.at = at
            self.below = below
            self.angle = angle
        }
    }

    /// The stage this figure draws one cycle of.
    public let stage: Stage
    public let strokes: [Stroke]
    public let labels: [Label]
    /// What a screen reader should say instead of describing a picture.
    public let description: String
    /// The ink extent of the drawing, control points included.
    ///
    /// Stored rather than computed: it is a pure function of `strokes`, which
    /// never change, and every renderer needs it once per stroke.
    ///
    /// Control points rather than the true curve extent: it over-estimates a
    /// cubic's reach by a little, which lands as margin rather than as a clipped
    /// wave.
    public let bounds: CGRect
    /// The strokes a renderer should actually draw, merged into one per pen.
    ///
    /// Every command list starts with a `move`, so runs that share a pen
    /// concatenate into one path with no visual change. A renderer makes one
    /// view per stroke, and merged, box breathing's four phases are three views
    /// instead of four — inside a 38-point list row.
    ///
    /// Stored for the same reason `bounds` is, and it is the stronger case of
    /// the two: the merge concatenates arrays as it folds, so recomputing it
    /// re-copied every command on every layout pass, at all four call sites.
    ///
    /// Ordered by first appearance so the baseline still lands under the line.
    public let drawable: [Stroke]

    /// A technique's figures, in play order — one per stage.
    ///
    /// Per stage rather than per technique because a staged protocol is a
    /// sequence of different exercises: a Wim Hof round is fast breathing, then
    /// one deep breath, then an open-ended retention, then a recovery hold, and
    /// each is its own drawing. One line spanning all of them would have to
    /// share a time axis with a stage that has no clock.
    public static func all(for technique: Technique) -> [Self] {
        technique.stages.map { Self(stage: $0) }
    }

    /// Draws one cycle of `stage` as the figure it appears as everywhere.
    public init(stage: Stage) {
        let rhythm = BreathRhythm(stage: stage)

        self.stage = stage
        strokes = Self.strokes(of: rhythm)
        bounds = Self.extent(of: strokes)
        labels = Self.labels(of: rhythm)
        description = Self.describe(stage: stage)
        drawable = Self.merge(strokes)
    }

    /// How to place this figure in a rect: uniform, centred, fitted to the ink.
    ///
    /// Here rather than in each renderer, and this is the piece that matters
    /// most. "The page and the app draw a technique the same way" is what the
    /// whole arrangement exists to guarantee, and placing the figure is the last
    /// step of drawing one — so a second copy of this rule is the one divergence
    /// `mise run check:diagrams` could never catch. It regenerates the site's
    /// SVG from whatever rule the generator holds, so two rules that disagree
    /// produce no diff at all and simply render at different scales.
    ///
    /// Uniform because stretching would warp the slopes against each other, and
    /// the ratio between a rise and a fall is the thing the drawing states.
    /// Fitted to `bounds` rather than the unit box because a retention's flat
    /// line reaches almost none of it, and fitting the box would centre the
    /// line in empty space.
    ///
    /// - Parameter lineWidth: the weight the figure will be stroked at. The rect
    ///   is inset by half of it, which is exactly what a stroke straddling the
    ///   path needs — asked for as the width rather than as the inset because
    ///   the four renderers had four answers to the same question, from the full
    ///   width down to nothing at all.
    public func transform(into rect: CGRect, lineWidth: CGFloat = 0) -> CGAffineTransform {
        Self.transform(fitting: bounds, into: rect, lineWidth: lineWidth)
    }

    /// The same rule against an extent the caller already holds — a renderer
    /// that draws one stroke at a time has the figure's `bounds` but not the
    /// figure.
    public static func transform(
        fitting bounds: CGRect,
        into rect: CGRect,
        lineWidth: CGFloat = 0
    ) -> CGAffineTransform {
        let inset = lineWidth / 2
        let available = rect.insetBy(dx: inset, dy: inset)
        guard bounds.width > 0 || bounds.height > 0, available.width > 0,
              available.height > 0
        else {
            return .identity
        }

        // A flat figure has no height to fit — an open-ended retention is one
        // horizontal line — so each axis only bids for the scale if the ink
        // extends along it. Requiring both left such a figure at identity: a
        // one-point speck where the drawing should span the rect.
        let scale = min(
            bounds.width > 0 ? available.width / bounds.width : .greatestFiniteMagnitude,
            bounds.height > 0 ? available.height / bounds.height : .greatestFiniteMagnitude
        )
        return CGAffineTransform(
            translationX: rect.midX - bounds.midX * scale,
            y: rect.midY - bounds.midY * scale
        )
        .scaledBy(x: scale, y: scale)
    }

    /// The extent of a set of strokes, control points included.
    private static func extent(of strokes: [Stroke]) -> CGRect {
        var minimum = CGPoint(x: CGFloat.greatestFiniteMagnitude, y: .greatestFiniteMagnitude)
        var maximum = CGPoint(x: -CGFloat.greatestFiniteMagnitude, y: -.greatestFiniteMagnitude)

        func include(_ point: CGPoint) {
            minimum.x = min(minimum.x, point.x)
            minimum.y = min(minimum.y, point.y)
            maximum.x = max(maximum.x, point.x)
            maximum.y = max(maximum.y, point.y)
        }

        for stroke in strokes {
            for command in stroke.commands {
                switch command {
                case let .move(point), let .line(point):
                    include(point)
                case let .curve(point, control1, control2):
                    include(point)
                    include(control1)
                    include(control2)
                }
            }
        }

        guard minimum.x <= maximum.x else {
            return CGRect(x: 0, y: 0, width: 1, height: 1)
        }
        return CGRect(
            x: minimum.x,
            y: minimum.y,
            width: maximum.x - minimum.x,
            height: maximum.y - minimum.y
        )
    }
}

public extension [TechniqueFigure] {
    /// A whole technique's figures as one sentence.
    ///
    /// The app hands this to VoiceOver and the generator writes it into the
    /// SVG's `aria-label`, so a technique is described identically wherever it
    /// is met. Here rather than joined at each call site, because "the same
    /// sentence" was previously a claim two doc comments made about each other.
    ///
    /// Deliberately **not** named `description`: that would shadow `Array`'s own
    /// `CustomStringConvertible` conformance, so string interpolation and every
    /// generic path would keep yielding the struct dump while these two call
    /// sites quietly got something else.
    var spoken: String {
        map(\.description).joined(separator: " ")
    }
}
