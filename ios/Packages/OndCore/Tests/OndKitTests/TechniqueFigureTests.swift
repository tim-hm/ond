import CoreGraphics
import Foundation
import OndKit
import Testing

/// The figure is what a person reads before deciding to breathe something, and
/// nothing else validates it. One construction draws every technique — one
/// cycle, inhale climbing, hold flat, exhale falling, slope as pace — and what
/// follows asserts the judgements that construction makes about the catalogue's
/// own numbers.
@Suite("Drawing a technique as a figure")
struct TechniqueFigureTests {
    /// The rule everything else stands on: every stage is one figure, every
    /// figure is one cycle, every phase is one stroke. The grammar this
    /// replaced could not say any of that — holds drew as polygons, hold-free
    /// stages as multi-cycle lines, and consecutive stages merged — so each
    /// renderer met a different kind of picture per exercise.
    @Test("Every seeded technique draws one figure per stage, one cycle each")
    func oneFigurePerStage() {
        for technique in SeededCatalogue.techniques {
            let figures = TechniqueFigure.all(for: technique)
            #expect(figures.count == technique.stages.count, "`\(technique.slug)`")

            for figure in figures {
                let strokes = figure.strokes.filter { $0.ink != .baseline }.count
                #expect(strokes == figure.stage.phases.count, "`\(technique.slug)`")
                // Wider than tall, always: the flattened band is what keeps a
                // slow breath's arc from reading as more time than an equal
                // hold's flat run.
                #expect(figure.bounds.height < figure.bounds.width, "`\(technique.slug)`")
            }
        }
    }

    /// Box breathing under the one construction: a climb, a plateau at full
    /// lungs, a fall, a floor at empty — four equal phases taking four equal
    /// quarters of the cycle.
    @Test("Box breathing rises, holds full, falls, and holds empty")
    func boxBreathing() {
        let rhythm = BreathRhythm(stage: SeededCatalogue.technique("box-breathing").stages[0])

        #expect(rhythm.segments.map(\.kind) == [.inhale, .holdIn, .exhale, .holdOut])
        #expect(rhythm.segments.map(\.endLevel) == [1, 1, 0, 0])
        for segment in rhythm.segments {
            #expect(abs((segment.end - segment.start) - 0.25) < 1e-9)
        }
    }

    /// A hold's slope is zero by meaning, not by accident of its duration.
    @Test("A hold keeps the level the breath before it reached")
    func holdsAreFlat() {
        for technique in SeededCatalogue.techniques {
            for stage in technique.stages {
                for segment in BreathRhythm(stage: stage).segments where segment.kind.isHold {
                    #expect(segment.startLevel == segment.endLevel, "`\(technique.slug)`")
                }
            }
        }
    }

    /// Slope is the channel that makes the line worth looking at: a four-second
    /// rise beside a six-second fall should be visibly steeper, in exactly the
    /// ratio of the two durations.
    @Test("Extended exhale falls more gently than it rises, in the ratio of its phases")
    func extendedExhaleSlopes() {
        let rhythm = BreathRhythm(stage: SeededCatalogue.technique("extended-exhale").stages[0])
        let rise = rhythm.segments[0]
        let fall = rhythm.segments[1]

        #expect(rise.kind == .inhale)
        #expect(fall.kind == .exhale)

        let rising = abs(rise.endLevel - rise.startLevel) / (rise.end - rise.start)
        let falling = abs(fall.endLevel - fall.startLevel) / (fall.end - fall.start)

        #expect(rising > falling)
        // 4 seconds in against 6 out, so the fall is two-thirds as steep.
        #expect(abs(falling / rising - 4.0 / 6.0) < 1e-9)
    }

    /// The asymmetry that names 4-7-8, stated by the one construction: the
    /// hold owns its seven nineteenths of the cycle, and the eight-second
    /// exhale falls at half the steepness of the four-second inhale.
    @Test("4-7-8 spends its cycle in the ratio of its name")
    func fourSevenEight() {
        let rhythm = BreathRhythm(stage: SeededCatalogue.technique("four-seven-eight").stages[0])

        #expect(rhythm.segments.map(\.kind) == [.inhale, .holdIn, .exhale])
        for (segment, share) in zip(rhythm.segments, [4.0 / 19, 7.0 / 19, 8.0 / 19]) {
            #expect(abs((segment.end - segment.start) - share) < 1e-9)
        }
    }

    /// Two consecutive inhales, and the second is a sip rather than half the
    /// climb: a near-full first breath, then the top tenth — the thing the
    /// technique is named for.
    @Test("The sigh's second inhale is a short top-up, not half the climb")
    func physiologicalSigh() {
        let rhythm = BreathRhythm(stage: SeededCatalogue.technique("physiological-sigh").stages[0])
        let first = rhythm.segments[0]
        let sip = rhythm.segments[1]

        #expect(first.kind == .inhale)
        #expect(sip.kind == .inhale)
        #expect(sip.endLevel == 1)
        #expect(abs(first.endLevel - (1 - BreathRhythm.sipShare)) < 1e-9)
    }

    /// The alternation rides on the labels, not the shape. The signed midline
    /// this replaced drew each breath on its own side, which was a construction
    /// nothing else used and a picture nothing else prepared a reader for; a
    /// letter beside the phase says the same thing in the reader's own
    /// alphabet.
    @Test("Alternate nostril stays one-sided and letters its breaths instead")
    func alternateNostrilLetters() {
        let figure = SeededCatalogue.figure("alternate-nostril")

        #expect(figure.labels.map(\.text) == [
            "in · 4 L", "out · 6 R", "in · 4 R", "out · 6 L",
        ])

        let rhythm = BreathRhythm(stage: SeededCatalogue.technique("alternate-nostril").stages[0])
        let oneSided = rhythm.segments.allSatisfy { $0.startLevel >= 0 && $0.endLevel >= 0 }
        #expect(oneSided)
    }

    /// A staged protocol is a sequence of different exercises, so each stage is
    /// its own drawing — the run-up, the deep breath, the retention, the
    /// recovery. Only the retention may draw dashed: a dash means "no length
    /// the clock owns", so a dashed breath beside it would say the person
    /// decides when that breath ends too.
    @Test("A Wim Hof round draws one figure per stage, and dashes only the retention")
    func wimHofRounds() {
        let figures = TechniqueFigure.all(for: SeededCatalogue.technique("wim-hof-rounds"))

        #expect(figures.count == 4)

        for (index, figure) in figures.enumerated() {
            let dashed = figure.strokes.contains { $0.dashed }
            #expect(dashed == (index == SeededCatalogue.retention), "stage \(index)")
        }
    }

    /// The retention has no length the clock owns, so it must not draw one.
    @Test("An open-ended retention draws flat and dashed")
    func openEndedRetention() {
        let stage = SeededCatalogue.technique("wim-hof-rounds").stages[SeededCatalogue.retention]
        let rhythm = BreathRhythm(stage: stage)

        let flat = rhythm.segments.allSatisfy { $0.startLevel == $0.endLevel }

        #expect(rhythm.dashed)
        #expect(flat)
    }

    /// Where the words sit: each label lies along the run it names — the climb
    /// and the full-lung hold over their lines, the fall and the empty-lung
    /// hold under theirs — with a breath's word tilted to its slope and a
    /// hold's level.
    @Test("Labels lie along the runs they name")
    func labelPlacement() {
        let labels = SeededCatalogue.figure("box-breathing").labels

        #expect(labels.map(\.below) == [false, false, true, true])
        #expect(labels.map(\.text) == ["in · 4", "hold · 4", "out · 4", "hold · 4"])
        // The inhale climbs (negative angle, y downwards), the exhale falls,
        // and both holds run level.
        #expect(labels[0].angle < 0)
        #expect(labels[1].angle == 0)
        #expect(labels[2].angle > 0)
        #expect(labels[3].angle == 0)
        // Anchored on the runs themselves: the full-lung hold on the band's
        // top, the empty-lung hold on its floor, each breath midway between.
        #expect(labels[1].at.y == 0)
        #expect(abs(labels[0].at.y - labels[3].at.y / 2) < 1e-9)
    }
}
