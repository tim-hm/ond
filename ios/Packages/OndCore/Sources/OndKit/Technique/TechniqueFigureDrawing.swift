import CoreGraphics
import Foundation

/// How a cycle becomes a figure: the S-curves, the labels, and the fold that
/// gathers strokes into one path per pen. `TechniqueFigure` holds what a
/// figure is; this file holds how one is drawn. Internal only because the
/// initialiser that calls these sits in the other file — a caller wanting
/// strokes wants a figure.
extension TechniqueFigure {
    /// Merges `strokes` into one per pen, for the renderers.
    static func merge(_ strokes: [Stroke]) -> [Stroke] {
        var order: [Stroke] = []

        for stroke in strokes {
            let match = order.firstIndex {
                $0.ink == stroke.ink && $0.dashed == stroke.dashed
            }

            if let match {
                order[match] = Stroke(
                    stroke.ink,
                    order[match].commands + stroke.commands,
                    dashed: stroke.dashed
                )
            } else {
                order.append(stroke)
            }
        }

        return order
    }

    // MARK: The line

    static func strokes(of rhythm: BreathRhythm) -> [Stroke] {
        // The empty-lungs baseline the curve rises from, spanning the cycle.
        let ground = place(0)
        var strokes = [Stroke(.baseline, [
            .move(to: CGPoint(x: 0, y: ground)),
            .line(to: CGPoint(x: 1, y: ground)),
        ])]

        for segment in rhythm.segments {
            let from = CGPoint(x: segment.start, y: place(segment.startLevel))
            let to = CGPoint(x: segment.end, y: place(segment.endLevel))

            let commands: [Command] = switch segment.kind {
            case .inhale, .exhale:
                // An S-curve, like the session orb's smoothstepped scale: a
                // breath does not change pace at its boundaries.
                [.move(to: from), .curve(
                    to: to,
                    control1: CGPoint(x: (from.x + to.x) / 2, y: from.y),
                    control2: CGPoint(x: (from.x + to.x) / 2, y: to.y)
                )]
            case .holdIn, .holdOut:
                [.move(to: from), .line(to: to)]
            }

            strokes.append(Stroke(Ink(segment.kind), commands, dashed: rhythm.dashed))
        }

        return strokes
    }

    /// Height of the cycle against its unit width — well under 1 because ink
    /// length lies about time: x carries duration, so at full height a
    /// 4-second inhale's arc runs about four times the length of the equal
    /// hold beside it. Flattening the band pulls the arc back towards its
    /// horizontal span while the slopes stay comparable.
    static let amplitude = 0.55

    /// A level onto the unit box's y, which runs downwards: empty lungs at the
    /// bottom of the band, full at the top.
    static func place(_ level: Double) -> CGFloat {
        CGFloat((1 - level) * amplitude)
    }

    static func labels(of rhythm: BreathRhythm) -> [Label] {
        runs(of: rhythm.segments).map { run in
            // The climb and the full-lung hold label over their runs; the fall
            // and the empty-lung hold label under theirs — each word beside
            // the line it names rather than banished to a band edge.
            let below = run[0].kind == .exhale || run[0].kind == .holdOut
            let from = CGPoint(x: run[0].start, y: place(run[0].startLevel))
            let to = CGPoint(
                x: run[run.count - 1].end,
                y: place(run[run.count - 1].endLevel)
            )

            return Label(
                text: word(for: run, dashed: rhythm.dashed),
                // The chord's midpoint, which for a breath's symmetric S-curve
                // is a point on the curve itself.
                at: CGPoint(x: (from.x + to.x) / 2, y: (from.y + to.y) / 2),
                below: below,
                // The tangent at the midpoint, not the chord's angle: the
                // symmetric cubic runs exactly twice as steep as its chord
                // there, so doubling the rise is that tangent in closed
                // form. A hold's zero rise stays zero.
                angle: atan2(Double(to.y - from.y) * 2, Double(to.x - from.x))
            )
        }
    }

    /// Consecutive segments of the same kind, grouped. The physiological
    /// sigh's two inhales are one gesture: `in · 1.5 + 0.7` reads as the
    /// double inhale it is, where two separate labels overlap and read as
    /// two breaths.
    static func runs(of segments: [BreathRhythm.Segment]) -> [[BreathRhythm.Segment]] {
        segments.reduce(into: [[BreathRhythm.Segment]]()) { runs, segment in
            if let last = runs.last, last[0].kind == segment.kind {
                runs[runs.count - 1].append(segment)
            } else {
                runs.append([segment])
            }
        }
    }

    /// `in · 1.5 + 0.7`, or `in · 4 L` where the air goes somewhere worth
    /// naming. Read straight off the segments — each carries its phase — so no
    /// stage has to be re-supplied and looked up by an index that could
    /// describe another one.
    static func word(for run: [BreathRhythm.Segment], dashed: Bool) -> String {
        guard let first = run.first?.phase else { return "" }

        guard !dashed else { return word(open: first) }

        return word(
            first.kind,
            lasting: run.map(\.phase.duration),
            passage: first.passage?.mark
        )
    }

    // MARK: Words

    /// `in · 4`, in the marketing site's idiom: middle-dot separator, no
    /// unit because every number on a figure is seconds. A run's durations
    /// join with `+` — the sigh's double breath. A passage mark rides on a
    /// space: `in · 4 L` reads as one item where `in · 4 · L` reads as three.
    static func word(
        _ kind: PhaseKind,
        lasting: [Duration],
        passage: String?
    ) -> String {
        let word = "\(name(of: kind)) · \(lasting.map(\.inSeconds).joined(separator: " + "))"
        return passage.map { "\(word) \($0)" } ?? word
    }

    /// `hold · 30s–2m`, for a phase of a stage the person ends rather than the
    /// clock. Its dialled duration is the first round's aim, and printing it
    /// would promise a length the session does not keep — but the catalogue's
    /// range is a band rather than a schedule, so a phase that has one shows it
    /// as the example it is. A single-point range keeps the word alone.
    static func word(open phase: Phase) -> String {
        guard let band = phase.range.band else { return name(of: phase.kind) }

        return "\(name(of: phase.kind)) · \(band)"
    }

    static func name(of kind: PhaseKind) -> String {
        switch kind {
        case .inhale: "in"
        case .exhale: "out"
        case .holdIn, .holdOut: "hold"
        }
    }

    /// What a screen reader says instead of the picture. The chart is hidden
    /// from VoiceOver, so this string carries the facts; it also becomes the
    /// generated SVG's `aria-label`, so the page and the app describe a
    /// technique identically.
    static func describe(stage: Stage) -> String {
        let cueRoles = stage.cueRoles
        let phases = stage.phases.enumerated().map { index, phase -> String in
            let instruction = cueRoles[index]
                .preparationInstruction(for: phase.breath, doneWith: phase.manner, in: .plain)

            guard !stage.openEnded else {
                let hold = "\(instruction), for as long as you can"
                return phase.range.spokenBand.map { "\(hold) — typically \($0)" } ?? hold
            }
            // Spelled out as a measurement rather than a number and a bare
            // "seconds", so a one-second bellows breath is not announced as
            // "for 1 seconds".
            return "\(instruction) for \(phase.duration.spokenLength)"
        }

        let cycle = phases.joined(separator: ", ")
        guard stage.cycles > 1 else { return "One cycle: \(cycle)." }
        return "One cycle: \(cycle). Repeated \(stage.cycles) times."
    }
}
