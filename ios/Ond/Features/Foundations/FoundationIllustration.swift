import OndUI
import SwiftUI

/// A line drawing for one foundation topic — the idea in the answer, sketched
/// at one stroke weight so a scroll through the basics reads as a single hand.
///
/// Keyed on the topic's slug, not its position: the topics arrive from the
/// seeded catalogue, so their wording and their order can both change without
/// the app shipping. A slug this file has never heard of draws nothing at all,
/// which is what lets the backend add a topic before the app has a picture for
/// it — a gap in the sketches, never a wrong one and never a crash.
struct FoundationIllustration: View {
    /// The topic's stable key, as seeded.
    let slug: String

    private static let height: CGFloat = 120

    var body: some View {
        switch slug {
        case "why-it-works": sketch(Sketches.seesaw)
        case "belly-or-chest": sketch(Sketches.torso)
        case "nose-or-mouth": sketch(Sketches.profile)
        case "how-to-exhale": sketch(Sketches.plume)
        case "how-slow": sketch(Sketches.waves)
        case "breathing-fast": sketch(Sketches.climb)
        case "holding-the-breath": sketch(Sketches.plateaus)
        case "sitting-or-lying": sketch(Sketches.postures)
        case "eyes-open-or-closed": sketch(Sketches.eyes)
        case "how-long": sketch(Sketches.sittings)
        case "long-term-benefits": sketch(Sketches.trend)
        default: EmptyView()
        }
    }

    private func sketch(_ strokes: [Stroke]) -> some View {
        Sketch(strokes: strokes)
            .frame(maxWidth: .infinity)
            .frame(height: Self.height)
            // Decoration. The question and answer beneath carry the meaning,
            // and VoiceOver reads them as one element without this in the way.
            .accessibilityHidden(true)
    }
}

/// One pen stroke: where it goes, and the colour it goes in.
private struct Stroke {
    let color: Color
    /// Draws into the design box — a fixed 240×120 grid, y downwards, so every
    /// sketch is authored at one scale and fitted to the row afterwards.
    ///
    /// `@Sendable` because the shape that ends up holding it is a `Shape`, and
    /// `Shape` is `Sendable` in the Swift 6 language mode.
    let draw: @Sendable (inout Path) -> Void

    /// A stroke of straight runs, one subpath per run — the shape most of these
    /// drawings are, and the one a closure spells out four lines at a time.
    static func lines(_ color: Color, _ runs: [[CGPoint]]) -> Stroke {
        Stroke(color: color) { path in
            for run in runs {
                path.addLines(run)
            }
        }
    }

    /// A stroke of ellipses: heads, eyes, weights, the dots on a trend.
    static func rings(_ color: Color, _ rects: [CGRect]) -> Stroke {
        Stroke(color: color) { path in
            for rect in rects {
                path.addEllipse(in: rect)
            }
        }
    }
}

/// Lays strokes over each other in the design box.
private struct Sketch: View {
    static let design = CGSize(width: 240, height: 120)

    let strokes: [Stroke]

    var body: some View {
        ZStack {
            ForEach(Array(strokes.enumerated()), id: \.offset) { _, stroke in
                Fitted(draw: stroke.draw)
                    .stroke(
                        stroke.color,
                        style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round)
                    )
            }
        }
    }
}

/// Scales a design-box path into whatever the row offers, uniformly and
/// centred. Uniform is the point: stretching to fill would oval the eyes and
/// flatten the seesaw's weights into lozenges.
private struct Fitted: Shape {
    let draw: @Sendable (inout Path) -> Void

    func path(in rect: CGRect) -> Path {
        var path = Path()
        draw(&path)

        let design = Sketch.design
        let scale = min(rect.width / design.width, rect.height / design.height)
        return path.applying(
            CGAffineTransform(
                translationX: rect.midX - design.width * scale / 2,
                y: rect.midY - design.height * scale / 2
            )
            .scaledBy(x: scale, y: scale)
        )
    }
}

private func pt(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
    CGPoint(x: x, y: y)
}

/// The drawings themselves, one per slug.
///
/// Each holds to the same two-tone rule: structure in ink, and exactly one
/// stroke in the accent — the thing the answer points at. That is what makes a
/// sketch legible without a caption, since none of them carry text.
private enum Sketches {
    private static let ink = Theme.Ink.secondary
    private static let faint = Theme.Ink.tertiary
    private static let accent = Theme.Accent.settle

    /// Why it works: breath as the lever on the nervous system. The out-breath
    /// is the heavier end, and the beam tips towards it.
    ///
    /// The beam runs through the fulcrum's apex rather than near it. A beam
    /// floating off its own pivot is the first thing the eye catches.
    static var seesaw: [Stroke] {
        [
            .lines(faint, [[pt(56, 104), pt(184, 104)]]),
            .lines(ink, [[pt(108, 104), pt(120, 80), pt(132, 104)]]),
            .lines(ink, [[pt(36, 62), pt(204, 98)]]),
            .rings(faint, [CGRect(x: 29, y: 48, width: 14, height: 14)]),
            .rings(accent, [CGRect(x: 192, y: 74, width: 24, height: 24)]),
        ]
    }

    /// Belly or chest: one seated body, a hand at the chest and a hand under
    /// the ribs, and only the low one with movement coming off it.
    static var torso: [Stroke] {
        [
            .rings(ink, [CGRect(x: 66, y: 8, width: 24, height: 24)]),
            Stroke(color: ink) { path in
                path.move(to: pt(70, 34))
                path.addCurve(to: pt(66, 104), control1: pt(60, 58), control2: pt(60, 84))
                path.addLine(to: pt(108, 104))
            },
            Stroke(color: ink) { path in
                path.move(to: pt(86, 36))
                path.addCurve(to: pt(100, 78), control1: pt(102, 46), control2: pt(100, 62))
                path.addCurve(to: pt(108, 104), control1: pt(100, 90), control2: pt(104, 98))
            },
            Stroke(color: faint) { path in
                hand(into: &path, y: 46)
            },
            Stroke(color: accent) { path in
                hand(into: &path, y: 76)
                path.addLines([pt(134, 72), pt(141, 69)])
                path.addLines([pt(136, 82), pt(144, 82)])
                path.addLines([pt(134, 92), pt(141, 95)])
            },
        ]
    }

    /// In through the nose: a profile, with the air arriving by the long way
    /// round rather than straight in at the mouth.
    static var profile: [Stroke] {
        [
            Stroke(color: ink) { path in
                path.move(to: pt(108, 10))
                path.addCurve(to: pt(146, 46), control1: pt(134, 12), control2: pt(148, 26))
                path.addCurve(to: pt(138, 74), control1: pt(145, 62), control2: pt(140, 68))
                path.addLine(to: pt(136, 104))
                path.move(to: pt(100, 104))
                path.addLine(to: pt(98, 90))
                path.addCurve(to: pt(92, 78), control1: pt(94, 86), control2: pt(88, 84))
                path.addCurve(to: pt(94, 68), control1: pt(96, 74), control2: pt(90, 72))
                path.addLine(to: pt(70, 62))
                path.addLine(to: pt(94, 44))
                path.addCurve(to: pt(94, 28), control1: pt(90, 38), control2: pt(92, 32))
                path.addCurve(to: pt(108, 10), control1: pt(98, 18), control2: pt(100, 12))
            },
            Stroke(color: accent) { path in
                path.move(to: pt(8, 84))
                path.addCurve(to: pt(66, 64), control1: pt(30, 82), control2: pt(50, 78))
            },
            Stroke(color: faint) { path in
                path.move(to: pt(10, 112))
                path.addCurve(to: pt(88, 86), control1: pt(38, 110), control2: pt(62, 102))
            },
        ]
    }

    /// And out through what: pursed lips, the accent breath long and level and
    /// the hurried one giving up a third of the way across.
    static var plume: [Stroke] {
        [
            .rings(ink, [CGRect(x: 20, y: 52, width: 22, height: 18)]),
            Stroke(color: faint) { path in
                path.move(to: pt(48, 50))
                path.addCurve(to: pt(108, 42), control1: pt(72, 44), control2: pt(92, 42))
            },
            Stroke(color: accent) { path in
                path.move(to: pt(48, 66))
                path.addCurve(to: pt(226, 64), control1: pt(110, 60), control2: pt(168, 70))
            },
        ]
    }

    /// How slow: the everyday breath in its own lane, and beneath it the long
    /// even swell of five or six a minute.
    ///
    /// Two lanes rather than one shared midline. Overlaid — which is how this
    /// drawing began — the quick wave reads as noise scribbled on the slow one
    /// instead of as a second pace.
    static var waves: [Stroke] {
        [
            Stroke(color: faint) { path in
                wave(into: &path, humps: 12, reach: 10, midline: 34)
            },
            Stroke(color: accent) { path in
                wave(into: &path, humps: 3, reach: 22, midline: 88)
            },
        ]
    }

    /// Breathing fast: the rapid breath climbing off the resting line, and the
    /// one long exhale that brings it back down.
    static var climb: [Stroke] {
        [
            .lines(faint, [[pt(12, 84), pt(228, 84)]]),
            Stroke(color: ink) { path in
                wave(into: &path, humps: 9, reach: 14, from: 14, to: 140, midline: 80, drift: -44)
            },
            Stroke(color: accent) { path in
                path.move(to: pt(140, 36))
                path.addCurve(to: pt(226, 84), control1: pt(170, 36), control2: pt(178, 84))
            },
        ]
    }

    /// Holding it: one breath with a pause at each end, the accent on the pause
    /// taken empty — the settling one of the two.
    static var plateaus: [Stroke] {
        [
            Stroke(color: ink) { path in
                path.move(to: pt(14, 92))
                path.addCurve(to: pt(52, 32), control1: pt(28, 92), control2: pt(34, 32))
            },
            .lines(faint, [[pt(52, 32), pt(100, 32)]]),
            Stroke(color: ink) { path in
                path.move(to: pt(100, 32))
                path.addCurve(to: pt(140, 92), control1: pt(118, 32), control2: pt(124, 92))
            },
            .lines(accent, [[pt(140, 92), pt(206, 92)]]),
            Stroke(color: ink) { path in
                path.move(to: pt(206, 92))
                path.addCurve(to: pt(226, 68), control1: pt(216, 92), control2: pt(218, 76))
            },
        ]
    }

    /// How long: one long sitting against the same minutes spread over a week.
    ///
    /// The two groups carry roughly equal area, so what the eye compares is how
    /// the time is divided rather than how much of it there is.
    static var sittings: [Stroke] {
        [
            .lines(faint, [[pt(12, 102), pt(228, 102)]]),
            .lines(faint, [sitting(x: 20, width: 56)]),
            .lines(
                accent,
                stride(from: CGFloat(112), through: 200, by: 22).map { sitting(x: $0, width: 12) }
            ),
        ]
    }

    /// Sit or lie down: upright for anything alerting, flat for anything meant
    /// to end in sleep — one drawing because the choice is between them.
    static var postures: [Stroke] {
        [
            .lines(faint, [
                [pt(12, 104), pt(100, 104)],
                [pt(132, 104), pt(228, 104)],
                [pt(118, 40), pt(118, 92)],
            ]),
            Stroke(color: accent) { path in
                path.addEllipse(in: CGRect(x: 22, y: 14, width: 20, height: 20))
                path.move(to: pt(32, 36))
                path.addCurve(to: pt(38, 76), control1: pt(30, 52), control2: pt(34, 62))
                path.addLine(to: pt(70, 76))
                path.addLine(to: pt(72, 104))
            },
            Stroke(color: ink) { path in
                path.addEllipse(in: CGRect(x: 137, y: 86, width: 18, height: 18))
                path.addLines([pt(155, 97), pt(190, 97), pt(206, 86), pt(218, 102)])
            },
        ]
    }

    /// Eyes open or closed: both offered, the closed one in the accent because
    /// it is the simpler place to start.
    static var eyes: [Stroke] {
        [
            Stroke(color: ink) { path in
                path.move(to: pt(20, 60))
                path.addQuadCurve(to: pt(92, 60), control: pt(56, 30))
                path.addQuadCurve(to: pt(20, 60), control: pt(56, 90))
            },
            .rings(ink, [
                CGRect(x: 44, y: 48, width: 24, height: 24),
                CGRect(x: 52, y: 56, width: 8, height: 8),
            ]),
            Stroke(color: accent) { path in
                path.move(to: pt(144, 50))
                path.addQuadCurve(to: pt(220, 50), control: pt(182, 76))
                path.addLines([pt(158, 68), pt(154, 80)])
                path.addLines([pt(182, 72), pt(182, 84)])
                path.addLines([pt(206, 68), pt(210, 80)])
            },
        ]
    }

    /// Long term: weeks along the bottom and a measurement climbing over them.
    ///
    /// The curve flattens rather than running off the top. The effects are the
    /// size of a habit, and the drawing should not promise more than that.
    static var trend: [Stroke] {
        [
            .lines(faint, [[pt(16, 26), pt(16, 102), pt(226, 102)]]),
            Stroke(color: accent) { path in
                path.move(to: pt(30, 88))
                path.addCurve(to: pt(214, 44), control1: pt(86, 76), control2: pt(140, 58))
            },
            .rings(accent, [(30, 88), (76, 76), (122, 66), (168, 54), (214, 44)].map { x, y in
                CGRect(x: x - 3, y: y - 3, width: 6, height: 6)
            }),
        ]
    }

    /// A flat hand resting against the body's front, fingers pointing back at
    /// it, drawn at whatever height the answer is talking about.
    private static func hand(into path: inout Path, y: CGFloat) {
        path.move(to: pt(126, y))
        path.addLine(to: pt(106, y + 2))
        path.addQuadCurve(to: pt(106, y + 10), control: pt(100, y + 6))
        path.addLine(to: pt(126, y + 10))
    }

    /// One session standing on the baseline: width is how long it ran, and the
    /// run is open at the bottom because the baseline is already drawn.
    private static func sitting(x: CGFloat, width: CGFloat) -> [CGPoint] {
        [pt(x, 102), pt(x, 58), pt(x + width, 58), pt(x + width, 102)]
    }

    /// Alternating humps across the box, one cubic each. `reach` is how far the
    /// control points pull off the midline rather than the height the curve
    /// reaches — a cubic only travels three quarters of the way to its
    /// controls, so the drawn wave is shallower than the number suggests.
    ///
    /// `drift` carries the midline itself across the run, which is what lets a
    /// wave climb while it oscillates.
    private static func wave(
        into path: inout Path,
        humps: Int,
        reach: CGFloat,
        from startX: CGFloat = 12,
        to endX: CGFloat = 228,
        midline: CGFloat = 60,
        drift: CGFloat = 0
    ) {
        let step = (endX - startX) / CGFloat(humps)

        path.move(to: pt(startX, midline))
        for hump in 0 ..< humps {
            let left = startX + CGFloat(hump) * step
            let base = midline + drift * CGFloat(hump) / CGFloat(humps)
            let next = midline + drift * CGFloat(hump + 1) / CGFloat(humps)
            let pull = (base + next) / 2 + (hump.isMultiple(of: 2) ? -reach : reach)
            path.addCurve(
                to: pt(left + step, next),
                control1: pt(left + step / 2, pull),
                control2: pt(left + step / 2, pull)
            )
        }
    }
}
