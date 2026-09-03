import Foundation
@testable import OndKit
import Testing

/// Where a practice changes shape, and what marks it — the stage and round
/// bells. Pinned against the seeded catalogue rather than a fixture, because
/// "which exercises have more than one stage" is a fact about the seed and the
/// bell exists for exactly those.
@Suite("The seam between stages")
struct StageSeamTests {
    /// A stage turns over once however many cycles it holds. Wim Hof's first
    /// stage is thirty breaths, and a bell on each of them would be the
    /// opposite of the point.
    @Test("A stage opens once, whatever it is made of")
    func aStageOpensOnce() {
        let technique = SeededCatalogue.technique("wim-hof-rounds")
        let timeline = SessionTimeline(technique: technique)

        // Every stage of every round, less the one the session opens on. A
        // round boundary is a turnover too — round two starts the thirty
        // breaths again, and that seam is as worth marking as the others.
        let openers = timeline.beats.filter(\.opensStage)
        let seams = timeline.rounds * technique.stages.count - 1
        #expect(openers.count == seams, "\(timeline.rounds) rounds of \(technique.stages.count)")
        #expect(Set(openers.map(\.stage)) == Set(0 ..< technique.stages.count))

        // Every opener is the top of its stage, not somewhere inside it.
        for beat in openers {
            #expect(beat.cycle == 0, "stage \(beat.stage) opened mid-cycle")
            #expect(beat.phase == 0, "stage \(beat.stage) opened mid-breath")
        }
    }

    /// A round boundary is a stage boundary too, and the larger of the two. Wim
    /// Hof is three rounds of four stages: eleven seams, of which two are rounds
    /// turning over. Pinned because the two bells differ, and the rule that
    /// separates them — a stage opening on stage zero — reads as an
    /// implementation detail until it is stated as a count.
    @Test("A round turning over is marked apart from a stage")
    func aRoundIsTheLargerSeam() {
        let technique = SeededCatalogue.technique("wim-hof-rounds")
        let timeline = SessionTimeline(technique: technique)

        let rounds = timeline.beats.filter(\.opensRound)
        #expect(rounds.count == timeline.rounds - 1, "one per round after the first")
        for beat in rounds {
            #expect(beat.stage == 0, "a round opened on stage \(beat.stage)")
            #expect(beat.opensStage, "a round turning over is a stage turning over")
        }

        // The rest are stages within a round, and outnumber them.
        let withinARound = timeline.beats.filter { $0.opensStage && !$0.opensRound }
        #expect(withinARound.count == timeline.rounds * (technique.stages.count - 1))
        for beat in withinARound {
            #expect(beat.stage != 0, "a stage seam sat where a round seam belongs")
        }
    }

    /// A sigh is one instruction even though phase boundaries divide it into
    /// three beats. Both doses read the same; only their timings differ.
    @Test("Both sighs read as one connected instruction")
    func sighsReadAsOneInstruction() {
        for slug: TechniqueSlug in ["physiological-sigh", "cyclic-sighing"] {
            let beats = Array(SeededCatalogue.timeline(slug).beats.prefix(3))

            #expect(beats.map(\.instruction) == ["Breathe in", "And in", "And breathe out"])
            #expect(beats.map(\.spokenInstruction) == [
                "Breathe in", "And in", "And breathe out",
            ])
            #expect(beats.map(\.stacksOnPrevious) == [false, true, false])
        }
    }

    /// A breath that reverses the one before it stacks on nothing. Bellows
    /// breath alternates all the way through, so it is the counter-case.
    @Test("Alternating breaths never stack")
    func alternatingBreathsNeverStack() {
        for slug: TechniqueSlug in ["bellows-breath", "box-breathing", "coherent-breathing"] {
            let beats = SeededCatalogue.timeline(slug).beats
            let stacked = beats.filter(\.stacksOnPrevious)
            #expect(stacked.isEmpty, "\(slug) stacked \(stacked.count) breaths")
        }
    }

    /// The session starting is not a stage changing — the countdown has already
    /// said so, and a bell on the first breath would ring over it.
    @Test("The first breath of a session opens nothing")
    func theFirstBeatIsSilent() {
        for technique in SeededCatalogue.techniques {
            let timeline = SessionTimeline(technique: technique)
            #expect(timeline.beats.first?.opensStage == false, "\(technique.slug) rang at the off")
        }
    }

    /// A single-stage exercise has no seam, so it never rings.
    @Test("A practice of one stage has nothing to mark")
    func oneStageNeverRings() {
        for technique in SeededCatalogue.techniques where technique.stages.count == 1 {
            let rings = SessionTimeline(technique: technique).beats.filter(\.opensStage)
            #expect(rings.isEmpty, "\(technique.slug) rang with nothing to mark")
        }
    }
}
