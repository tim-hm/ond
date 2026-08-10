import CoreGraphics
import Foundation

/// Turning the cycle's geometry into the strokes and labels a renderer draws.
///
/// Split from `TechniqueFigure` itself, which holds what a figure *is* — the
/// command vocabulary, the extent every renderer fits. This file holds how a
/// cycle becomes one: the S-curves, where each label hangs, the words that go
/// on them, and the fold that gathers the strokes into one path per pen.
///
/// Internal rather than private only because the initialiser that calls these
/// sits in the other file. Nothing outside `TechniqueFigure` should reach for
/// them: a caller wanting strokes wants a figure.
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

    static func ink(_ kind: PhaseKind) -> Ink {
        switch kind {
        case .inhale: .inhale
        case .exhale: .exhale
        case .holdIn, .holdOut: .hold
        }
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

            strokes.append(Stroke(ink(segment.kind), commands, dashed: rhythm.dashed))
        }

        return strokes
    }

    /// How tall the cycle draws against its unit width — a wide band rather
    /// than a square.
    ///
    /// Deliberately well under 1, because ink length lies about time: x carries
    /// duration, so a breath draws a diagonal arc while an equal hold draws a
    /// short flat run, and the taller the rise the worse the lie — at full
    /// height a 4-second inhale's arc is about four times the length of the
    /// 4-second hold beside it. Flattening the band pulls a breath's arc back
    /// towards its horizontal span (roughly 2.4× on box breathing at this
    /// value) while the slopes stay comparable, and the figure reads as the
    /// waveform it is.
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
                angle: atan2(Double(to.y - from.y), Double(to.x - from.x))
            )
        }
    }

    /// Consecutive segments of the same kind, grouped.
    ///
    /// The physiological sigh's two inhales are one gesture — a breath and a sip
    /// on top of it — and labelling them separately puts two words in the space
    /// of one, overlapping. Grouping also states the thing the exercise is named
    /// for: `in · 1.5 + 0.7` reads as a double inhale, where two labels read as
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

    /// `in · 1.5 + 0.7`, or `in · 4 L` where a nostril is named. Read straight
    /// off the segments — each carries its phase — so no stage has to be
    /// re-supplied and looked up by an index that could describe another one.
    static func word(for run: [BreathRhythm.Segment], dashed: Bool) -> String {
        guard let first = run.first?.phase else { return "" }

        return word(
            first.kind,
            lasting: run.map(\.phase.duration),
            dashed: dashed,
            nostril: first.passage?.mark
        )
    }

    // MARK: Words

    /// `in · 4`, in the marketing site's own idiom. The separator is the site's
    /// middle dot rather than a colon, and the unit is left off because every
    /// number on a figure is seconds.
    ///
    /// An open-ended phase gets the word alone: its seeded duration describes a
    /// typical hold, and printing it would promise a length the session does not
    /// keep.
    ///
    /// - Parameters:
    ///   - lasting: one duration per phase in the run. The sigh's two inhales
    ///     join with a `+`, which reads as the double breath it is.
    ///   - nostril: `L` or `R`, riding on a space rather than another middle dot
    ///     — `in · 4 L` reads as one item where `in · 4 · L` reads as three.
    static func word(
        _ kind: PhaseKind,
        lasting: [Duration],
        dashed: Bool,
        nostril: String? = nil
    ) -> String {
        guard !dashed else { return name(of: kind) }

        let word = "\(name(of: kind)) · \(lasting.map(\.inSeconds).joined(separator: " + "))"
        return nostril.map { "\(word) \($0)" } ?? word
    }

    static func name(of kind: PhaseKind) -> String {
        switch kind {
        case .inhale: "in"
        case .exhale: "out"
        case .holdIn, .holdOut: "hold"
        }
    }

    /// What a screen reader says instead of the picture.
    ///
    /// This is not decoration: the phone's chart is hidden from VoiceOver, and
    /// the row of phase capsules that used to carry these facts as text is gone
    /// now the figure carries its own labels. The same string becomes the
    /// generated SVG's `aria-label`, so the page and the app describe a
    /// technique identically.
    ///
    /// The figure always draws exactly one cycle, so unlike the labels the
    /// sentence needs no notion of what is on the page — the repeat count is
    /// the stage's own.
    static func describe(stage: Stage) -> String {
        let phases = stage.phases.map { phase -> String in
            let instruction = phase.breath.spokenInstruction

            guard !stage.openEnded else { return "\(instruction), for as long as you can" }
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
