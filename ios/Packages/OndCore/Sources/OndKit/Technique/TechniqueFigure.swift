import CoreGraphics
import Foundation

/// One stage of a technique drawn as one cycle: lung fullness over time.
/// Geometry only — the phone's chart and list row, the watch glyph, and the
/// site's SVG generator all render from this, so the shape is decided once.
/// Coordinates are a unit box with y downwards. A renderer fits `bounds`, not
/// the unit box: an open-ended retention is one flat line.
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

        /// Both holds are one ink: a rest at the bottom of a box is still a
        /// held breath. Public so the exercises list's bars share the mapping
        /// rather than keep a second copy that can disagree.
        public init(_ phase: PhaseKind) {
            switch phase {
            case .inhale: self = .inhale
            case .exhale: self = .exhale
            case .holdIn, .holdOut: self = .hold
            }
        }
    }

    /// One pen instruction. Deliberately the smallest set that draws every
    /// figure — a line for the holds and the baseline, and a cubic for the
    /// S-curve of a breath.
    public enum Command: Sendable, Equatable {
        case move(to: CGPoint)
        case line(to: CGPoint)
        case curve(to: CGPoint, control1: CGPoint, control2: CGPoint)

        /// Where the pen ends up. The control points of a curve are not it —
        /// they steer the line without ever being on it.
        public var point: CGPoint {
            switch self {
            case let .move(point), let .line(point), let .curve(point, _, _): point
            }
        }
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

        /// A baseline is reference, not subject: a hairline whatever weight
        /// the figure carries. Here rather than in `OndStyle` because the SVG
        /// generator cannot see that module, and a renderer's own copy of the
        /// rule is a divergence `mise run check:diagrams` cannot catch.
        public func weight(on lineWidth: CGFloat) -> CGFloat {
            ink == .baseline ? 1 : lineWidth
        }

        /// The dash a person-timed phase draws in — on for four, off for five,
        /// in the same units as the line width. Shared with the site for the
        /// reason above: an open-ended retention that dashed differently in the
        /// two places would look like two different exercises.
        public static let dash: [CGFloat] = [4, 5]
    }

    /// A word on the figure — `in · 4`. Each label lies along the run it
    /// names: a hold's word sits level, a breath's word tilts to its slope —
    /// anchored at the run's midpoint and pushed clear along the perpendicular.
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
    /// The ink extent, control points included: that over-estimates a cubic's
    /// reach a little, which lands as margin rather than a clipped wave.
    /// Stored because it is a pure function of `strokes`, and every renderer
    /// needs it once per stroke.
    public let bounds: CGRect
    /// The strokes a renderer should draw, merged into one path per pen.
    /// Every command list starts with a `move`, so runs that share a pen
    /// concatenate with no visual change. Stored: recomputing re-copied every
    /// command on every layout pass. Ordered by first appearance so the
    /// baseline still lands under the line.
    public let drawable: [Stroke]

    /// A technique's figures, in play order — one per stage. Per stage
    /// because a staged protocol is a sequence of different exercises, and
    /// one line spanning them would share a time axis with a stage that has
    /// no clock.
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

    /// Places the figure in a rect: uniform, centred, fitted to the ink, with
    /// the rect inset by half `lineWidth` — what a stroke straddling the path
    /// needs. Uniform because stretching would warp the rise/fall ratio the
    /// drawing states; fitted to `bounds` rather than the unit box so a
    /// retention's flat line is not centred in empty space.
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

    /// The full-lungs reference line at `place(1)` — faint, dashed. Not in
    /// `strokes`: only the site's hero plot draws it. A figure that never
    /// fills the lungs still gets it above its own ink — clamped down, a
    /// shallow breath would look like a full one. A renderer drawing it fits
    /// `boundsIncludingCeiling`.
    public var ceiling: Stroke {
        let top = Self.place(1)
        return Stroke(
            .baseline,
            [.move(to: CGPoint(x: 0, y: top)), .line(to: CGPoint(x: 1, y: top))],
            dashed: true
        )
    }

    /// What a renderer drawing the ceiling fits, rather than `bounds`. The
    /// union lives here so two renderers cannot fit it differently and put
    /// the ceiling outside its own frame.
    public var boundsIncludingCeiling: CGRect {
        bounds.union(Self.extent(of: [ceiling]))
    }

    /// Where one phase hands over to the next, in play order and without
    /// repeats. Derived from `strokes`, not `drawable`: the merge joins a
    /// box's two holds into one path and hides their junction. Computed, not
    /// stored — wanted once, at generate time, by one renderer.
    public var boundaries: [CGPoint] {
        var points: [CGPoint] = []

        for stroke in strokes where stroke.ink != .baseline {
            for point in [stroke.commands.first, stroke.commands.last].compactMap({ $0?.point }) {
                guard !points.contains(point) else { continue }
                points.append(point)
            }
        }

        return points
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
    /// A whole technique's figures as one sentence, handed to VoiceOver and
    /// written into the SVG's `aria-label`, so both say the same thing.
    /// Deliberately not named `description`: that would shadow `Array`'s
    /// `CustomStringConvertible` conformance, and interpolation would keep
    /// yielding the struct dump.
    var spoken: String {
        map(\.description).joined(separator: " ")
    }
}
