import CoreGraphics
import Foundation

/// One stage of a technique as a drawing: what shape it is, what colour each
/// part of it takes, what the parts are labelled, and how to say it aloud.
///
/// **One rule picks the family: corners are where the breath stops.** A cycle
/// that holds has real corners and draws as a polygon — box breathing a square,
/// 4-7-8 a triangle. A cycle that never holds has nothing to corner on and draws
/// as a line whose slope carries the timing. The alternative was the grammar
/// this replaced, which drew every technique as a rounded square varying only in
/// corner radius: five of the nine seeded techniques never hold, so all five
/// came out an identical circle, and coherent breathing and bellows breath — 5½
/// breaths a minute and twenty fast ones — were the same picture.
///
/// Geometry only, and deliberately no SwiftUI. Four renderers stand on this: the
/// phone's chart and its list row, the watch's carousel glyph, and the generator
/// that redraws the marketing site's figures (`mise run generate:diagrams`). A
/// technique is the same shape in all four because the shape is decided once,
/// here, and each renderer only turns commands into its own kind of path.
///
/// Coordinates are a unit box with y downwards. A renderer fits `bounds` rather
/// than the unit box: a triangle inscribed in the unit circle leaves corners of
/// empty space, and fitting the box instead would shrink every figure to make
/// room for nothing.
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
        /// The reference line a one-sided figure sits on, or the midline a
        /// signed one is measured from. Drawn faint, and never the subject.
        case baseline
    }

    /// One pen instruction. Deliberately the smallest set that draws every
    /// figure in the catalogue — a quadratic for the polygons' rounded corners,
    /// a cubic for the S-curve of a breath, and a circle for the dot that marks
    /// where the breath starts.
    public enum Command: Sendable, Equatable {
        case move(to: CGPoint)
        case line(to: CGPoint)
        case quadCurve(to: CGPoint, control: CGPoint)
        case curve(to: CGPoint, control1: CGPoint, control2: CGPoint)
        case circle(centre: CGPoint, radius: CGFloat)
    }

    /// Which of the two grammars a figure is drawn in.
    ///
    /// Named rather than left to be inferred. The renderers do not branch on it
    /// — they draw whatever `fill` and `drawable` hand them, which is the point
    /// — but the construction below does, and the tests assert on it, so the
    /// grammar a figure belongs to should be something the type says rather than
    /// something a reader reconstructs from a stroke count or an empty `fill`.
    /// Those are drawing details that happen to correlate, and one of them
    /// already went wrong: a wash was laid inside every hold-free technique
    /// because "three or more strokes" was standing in for "this is a closed
    /// figure".
    public enum Family: Sendable, Equatable {
        /// A closed polygon, with a corner at every phase boundary.
        case polygon
        /// An open line — lung fullness over time.
        case line
    }

    /// What a stroke is *for*, as opposed to what colour it takes.
    public enum Role: Sendable, Equatable {
        /// One phase of the breath: the thing being drawn.
        case phase
        /// The reference line a figure is measured against.
        case baseline
        /// The dot marking where the breath starts.
        case start
    }

    public struct Stroke: Sendable, Equatable {
        public let ink: Ink
        public let role: Role
        public let commands: [Command]
        /// Whether to draw this stroke dashed — an open-ended stage, whose
        /// durations describe a typical pass rather than a scheduled one.
        public let dashed: Bool

        public init(
            _ ink: Ink,
            _ role: Role = .phase,
            _ commands: [Command],
            dashed: Bool = false
        ) {
            self.ink = ink
            self.role = role
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
            role == .baseline ? 1 : lineWidth
        }

        /// The dash a person-timed phase draws in — on for four, off for five,
        /// in the same units as the line width. Shared with the site for the
        /// reason above: an open-ended retention that dashed differently in the
        /// two places would look like two different exercises.
        public static let dash: [CGFloat] = [4, 5]
    }

    /// A word on the figure — `in · 4`, or `L`. The site labels its figures this
    /// way and the app now does too, which is what let the colour key underneath
    /// the chart go: a reader who has to decode a legend is reading twice.
    public struct Label: Sendable, Equatable {
        public let text: String
        /// Where the label hangs, in the same unit box as the strokes.
        public let at: CGPoint
        /// Which way the label sits from `at`, so a renderer can push it clear
        /// of the line without knowing the geometry that produced it.
        public let away: CGVector

        public init(text: String, at: CGPoint, away: CGVector) {
            self.text = text
            self.at = at
            self.away = away
        }
    }

    /// One stage of a figure: which stage it is, and how much of it is drawn.
    public struct Drawn: Sendable, Equatable {
        /// Where the stage sits in the technique, numbered from zero.
        public let index: Int
        public let stage: Stage
        /// How many of its cycles are on the page.
        ///
        /// Rarely `stage.cycles`, and never by coincidence: a polygon is one lap
        /// however often the stage repeats, and a line draws whatever its window
        /// holds — two of coherent breathing's twenty-seven, six of bellows
        /// breath's twenty. While a figure carried only the stage's own count it
        /// announced twenty-seven cycles over a drawing of two.
        ///
        /// Taken from the branch that draws, so the count comes from the same
        /// geometry as the strokes rather than from a second reading of the
        /// stage.
        public let cycles: Int
    }

    /// The radius of the dot marking where the breath starts, in unit-box terms.
    ///
    /// A closed figure has no beginning to find and no direction to read; the
    /// colours only resolve it once you already know which way round it goes.
    /// This is the one mark that says where to put your finger.
    static let startRadius: CGFloat = 0.022

    public let family: Family
    public let strokes: [Stroke]
    public let labels: [Label]
    /// The closed outline, for the wash a renderer may lay inside a polygon.
    /// Empty for a line, which encloses nothing.
    public let fill: [Command]
    /// The stages this figure draws, in play order, each with how much of it is
    /// on the page.
    ///
    /// Usually one. A run of clock-timed line stages shares a drawing, because
    /// the breath does not stop between them, and then a caller that needs to
    /// title the figure or count what it announces has to be told which stages
    /// it stands for rather than inferring it from a position in a list that no
    /// longer matches.
    public let drawn: [Drawn]
    /// What a screen reader should say instead of describing a picture.
    public let description: String
    /// The ink extent of the drawing, control points included.
    ///
    /// Stored rather than computed: it is a pure function of `strokes`, which
    /// never change, and every renderer needs it once per stroke — so a
    /// computed property walked all fourteen of bellows breath's strokes
    /// fourteen times per pass on any call site that forgot to hoist it.
    ///
    /// Control points rather than the true curve extent: it over-estimates a
    /// cubic's reach by a little, which lands as margin rather than as a clipped
    /// wave.
    public let bounds: CGRect
    /// The strokes a renderer should actually draw, merged into one per pen.
    ///
    /// Every command list starts with a `move`, so runs that share a pen
    /// concatenate into one path with no visual change. That matters because a
    /// renderer makes one view per stroke: bellows breath's six cycles are
    /// fourteen strokes, and drawing them merged is four views instead of
    /// fourteen — inside a 38-point list row, fourteen times over.
    ///
    /// Stored for the same reason `bounds` is, and it is the stronger case of
    /// the two: the merge concatenates arrays as it folds, so recomputing it
    /// re-copied every command on every layout pass, at all four call sites.
    ///
    /// Ordered by first appearance so the baseline still lands under the line
    /// and the start dot still lands on top of it.
    public let drawable: [Stroke]

    /// A technique's figures, in play order — one per stage, except where
    /// consecutive stages draw as one line.
    ///
    /// Per stage rather than per technique because a staged protocol mixes
    /// families: a Wim Hof round is a rapid line, then one deep breath, then an
    /// open-ended retention, then a three-phase recovery that is a triangle. One
    /// drawing spanning all of them would have to pick a grammar and
    /// misrepresent the rest.
    public static func all(for technique: Technique) -> [Self] {
        runs(of: technique.stages).map { Self(technique.stages[$0]) }
    }

    /// Which stages draw together.
    ///
    /// Consecutive clock-timed lines join, because nothing happens to the breath
    /// at the boundary between them: the thirty fast breaths of a Wim Hof round
    /// and the one deep breath that follows are separate stages only because
    /// they repeat different numbers of times, and drawn apart they read as two
    /// exercises with a gap between them rather than as the run-up to a hold.
    ///
    /// Nothing else joins. A polygon is a closed lap with no loose end to
    /// continue from, and an open-ended stage has no clock, so it cannot share a
    /// time axis with breathing that does.
    private static func runs(of stages: [Stage]) -> [Range<Int>] {
        var runs: [Range<Int>] = []
        var continues = false

        for (index, stage) in stages.enumerated() {
            let joins = !BreathPolygon.suits(stage) && !stage.openEnded

            if joins, continues, let last = runs.last {
                runs[runs.count - 1] = last.lowerBound ..< index + 1
            } else {
                runs.append(index ..< index + 1)
            }
            continues = joins
        }

        return runs
    }

    /// - Parameter stages: the stages to draw as one figure. A slice rather than
    ///   an array so it carries the positions its stages hold in the technique,
    ///   which is what a caller titles the drawing from.
    public init(_ stages: ArraySlice<Stage>) {
        if let stage = stages.first, stages.count == 1, BreathPolygon.suits(stage) {
            let polygon = BreathPolygon(stage: stage)
            family = .polygon
            strokes = Self.strokes(of: polygon)
            labels = Self.labels(of: polygon, phases: stage.phases)
            fill = polygon.outline
            // A closed figure has room for exactly one lap: its corners are one
            // cycle's phase boundaries, and a second lap would retrace the first.
            drawn = [Drawn(index: stages.startIndex, stage: stage, cycles: 1)]
        } else {
            let rhythm = BreathRhythm(stages: Array(stages))
            family = .line
            strokes = Self.strokes(of: rhythm)
            labels = Self.labels(of: rhythm)
            // A line encloses nothing, so there is nothing to wash. Taken from
            // the branch that knows the family rather than inferred later from
            // a stroke count — which is what let every hold-free technique pick
            // up a gradient across a path it never draws.
            fill = []
            drawn = stages.indices.map { index in
                Drawn(
                    index: index,
                    stage: stages[index],
                    cycles: rhythm.drawn[index - stages.startIndex]
                )
            }
        }

        // After the branch, deliberately: the sentence states how many cycles
        // are on the page, so it has to be written by whichever grammar put
        // them there rather than ahead of the choice. One sentence per stage,
        // joined the way `spoken` joins figures, so merging two stages into one
        // drawing leaves what a screen reader hears exactly as it was.
        description = drawn
            .map { Self.describe(stage: $0.stage, drawn: $0.cycles) }
            .joined(separator: " ")
        bounds = Self.extent(of: strokes)
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
    /// Uniform because stretching would oval the start dot and turn box
    /// breathing's square into a rectangle — the one thing that drawing exists
    /// to say. Fitted to `bounds` rather than the unit box because a triangle
    /// inscribed in the unit circle leaves two corners of empty space, and
    /// fitting the box would shrink every figure to make room for nothing.
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
        guard bounds.width > 0, bounds.height > 0, available.width > 0, available.height > 0 else {
            return .identity
        }

        let scale = min(available.width / bounds.width, available.height / bounds.height)
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
                case let .quadCurve(point, control):
                    include(point)
                    include(control)
                case let .curve(point, control1, control2):
                    include(point)
                    include(control1)
                    include(control2)
                case let .circle(centre, radius):
                    include(CGPoint(x: centre.x - radius, y: centre.y - radius))
                    include(CGPoint(x: centre.x + radius, y: centre.y + radius))
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
