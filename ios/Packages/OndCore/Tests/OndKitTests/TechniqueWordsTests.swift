import Foundation
@testable import OndKit
import Testing

/// The sentences an exercise's own screen says about it, over the catalogue they
/// describe.
///
/// These lived in the app target until the words moved here, which is why they had
/// no tests: `ios/Ond/` has no test bundle, so four dose phrasings and a
/// nose-is-silent exception were curation rules over the seeded exercises that
/// nothing checked.
@Suite("What an exercise's screen says about it")
struct TechniqueWordsTests {
    private func technique(_ slug: String) -> Technique {
        SeededCatalogue.technique(slug)
    }

    @Test("A cyclic exercise states its cycles and length without commentary")
    func aCyclicExerciseStatesItsDose() {
        #expect(
            technique("box-breathing").doseDescription
                == "19 cycles, about 5 minutes."
        )
    }

    @Test("A one-cycle exercise uses the singular dose")
    func aOneCycleExerciseStatesItsDose() {
        let box = technique("box-breathing")
        var overrides = box.curatedOverrides
        overrides.stages[0].cycles = 1

        #expect(box.dialled(with: overrides).doseDescription == "One cycle, about 16 seconds.")
    }

    /// A staged protocol is counted in rounds, and one of its stages ends when the
    /// person does — so the total is an estimate and the sentence has to say so
    /// rather than printing a number the clock will not keep.
    @Test("An open-ended protocol says its length is an estimate")
    func anOpenEndedProtocolHedgesItsLength() {
        let dose = technique("wim-hof-rounds").doseDescription

        #expect(dose.hasPrefix("3 rounds, around "))
        #expect(dose.hasSuffix("depending on how long your holds run."))
        #expect(!dose.contains("However many you do"))
    }

    /// One unit, never two. "2 min, 8 secs" is a readout; this is read inside a
    /// sentence, and the seconds are noise against the "about" in front of them.
    @Test("A length inside a sentence is spelled to one unit")
    func aLengthIsSpelledToOneUnit() {
        #expect(technique("box-breathing").plannedDuration.spelled == "5 minutes")
        #expect(technique("box-breathing").plannedDuration.glanceable == "5 min")
        #expect(technique("physiological-sigh").plannedDuration.spelled == "22 seconds")
    }

    /// A session leaves the two holds reading alike, because the breath before a
    /// hold says which one it is. A list of all four has no such order, so an
    /// editing screen would otherwise offer two identical rows and no way to tell
    /// which one a stepper was about to move.
    @Test("The two holds read alike in a sequence and apart in a list")
    func theHoldsPartWhereOrderCannotTellThem() {
        #expect(PhaseKind.holdIn.instruction == PhaseKind.holdOut.instruction)
        #expect(PhaseKind.holdIn.standaloneTitle != PhaseKind.holdOut.standaloneTitle)
        #expect(PhaseKind.inhale.standaloneTitle == PhaseKind.inhale.instruction)
    }

    /// The rule `Passage.hint` states, applied to every line of a how-to: the nose is
    /// what the foundations teach and what most of the catalogue does throughout, so
    /// naming it on every step of every exercise is the noise that stops the other
    /// ones being read.
    @Test("Breathing through the nose throughout is left unsaid")
    func theNoseGoesUnmentioned() {
        let steps = technique("box-breathing").stages.flatMap(\.steps)

        #expect(steps.map(\.instruction) == ["Breathe in", "Hold", "Breathe out", "Hold"])
        #expect(steps.allSatisfy { !$0.instruction.contains("through") })
    }

    /// A sigh is one instruction spread across three rows. The exact shape is
    /// what connects it, so both seeded doses and a personal exercise built to
    /// the same shape say the same route-neutral sentence.
    @Test("Both sighs read as one connected instruction")
    func sighsUseConnectedInstructions() {
        for slug in ["physiological-sigh", "cyclic-sighing"] {
            let steps = technique(slug).stages.flatMap(\.steps)
            #expect(steps.map(\.instruction) == [
                "Breathe in", "And in", "And breathe out",
            ])
        }

        let custom = Stage(
            phases: [
                Phase(kind: .inhale, duration: .seconds(3)),
                Phase(kind: .inhale, duration: .seconds(1)),
                Phase(kind: .exhale, duration: .seconds(6)),
            ],
            cycles: 1
        )
        #expect(custom.steps.map(\.instruction) == [
            "Breathe in", "And in", "And breathe out",
        ])

        let physiological = technique("physiological-sigh").stages.flatMap(\.steps)
        #expect(physiological.map(\.count) == ["1.5s", "1s", "5s"])
    }

    /// The mouth is part of standard 4-7-8 instructions, so this is the place
    /// the default nasal route becomes explicit rather than staying silent.
    @Test("4-7-8 names its mouth exhale")
    func fourSevenEightNamesItsMouthExhale() {
        let steps = technique("four-seven-eight").stages.flatMap(\.steps)

        #expect(steps.map(\.instruction) == [
            "Breathe in", "Hold", "Breathe out through your mouth",
        ])
        #expect(steps.map(\.count) == ["4s", "7s", "8s"])
    }

    @Test("Sigh copy treats a mouth exhale as optional")
    func sighCopyMakesTheMouthOptional() {
        let physiological = technique("physiological-sigh").mechanism ?? ""
        let cyclic = technique("cyclic-sighing").mechanism ?? ""

        #expect(physiological.contains("the route is a comfort choice"))
        #expect(cyclic.contains("it is optional"))
        #expect(cyclic.contains("use the nose when comfortable"))
    }

    /// The case the single `passageNote` sentence this replaced gave up on. It went
    /// silent for alternating nostrils, because one sentence cannot say "alternating,
    /// and which hand closes which" without being wrong. A line per phase does not
    /// have to: it simply says which nostril this breath goes through.
    @Test("Alternating nostrils is named a breath at a time")
    func alternatingNostrilsIsNamedPerBreath() {
        let steps = technique("alternate-nostril").stages.flatMap(\.steps)

        #expect(steps.map(\.instruction) == [
            "Breathe in through your left nostril",
            "Breathe out through your right nostril",
            "Breathe in through your right nostril",
            "Breathe out through your left nostril",
        ])
    }

    /// A retention takes its band where every other phase takes a count. The
    /// session clock stops for one — its dialled duration is the first round's
    /// aim rather than a scheduled length — so a single number here would be a
    /// count nothing keeps, and the range brackets the hold instead.
    @Test("A hold the person ends is bracketed, not counted")
    func anOpenEndedHoldIsBracketed() {
        let retention = technique("wim-hof-rounds").stages.first { $0.openEnded }

        #expect(retention?.steps.map(\.count) == ["30s–2m"])
        #expect(retention?.steps.map(\.instruction) == ["Hold"])
    }

    /// The bug this file was written after. `dialled(with:)` rebuilt the type field
    /// by field against an initialiser whose tail parameters all default, so it
    /// dropped `mechanism` — and the detail screen is handed the dialled copy, so
    /// the paragraph reached the export, the decoder and its own test, then died one
    /// call short of the only screen that renders it.
    @Test("A dialled copy keeps everything a dial did not touch")
    func aDialledCopyKeepsTheCuratedCopy() {
        let curated = technique("box-breathing")
        let dialled = curated.dialled(with: TechniqueOverrides(
            stages: [
                StageDialling(phaseDurationsMs: [5000, 5000, 5000, 5000], cycles: 4),
            ],
            rounds: 1
        ))

        #expect(dialled.stages.first?.cycles == 4)
        #expect(dialled.mechanism == curated.mechanism)
        #expect(dialled.mechanism != nil)
        #expect(dialled.evidence == curated.evidence)
        #expect(dialled.evidence != nil)
        #expect(dialled.summary == curated.summary)
        #expect(dialled.safetyNote == curated.safetyNote)
        #expect(dialled.requires == curated.requires)
        #expect(dialled.origin == curated.origin)
    }

    /// The same rule one type down, where it does not hold by construction.
    ///
    /// `Technique.replacing` copies, so it cannot forget a field. `Phase.dialled`
    /// rebuilds against an initialiser whose tail parameters default, which is
    /// exactly how `requires`, `origin` and `mechanism` were each silently lost
    /// on the technique before it was made a copy — and a manner lost here would
    /// not fail anything: the cooling breath would simply stop mentioning the
    /// tongue the moment somebody opened Customise.
    @Test("Dialling a phase keeps the shape a dial cannot move")
    func aDialledPhaseKeepsItsManner() {
        let curated = technique("cooling-breath")
        #expect(curated.stages[0].phases[0].manner == .curledTongue)

        let phase = curated.stages[0].phases[0]
        #expect(phase.dialled(to: .seconds(5)).manner == .curledTongue)

        let dialled = curated.dialled(with: TechniqueOverrides(
            stages: [StageDialling(phaseDurationsMs: [5000, 5000], cycles: 4)],
            rounds: 1
        ))
        #expect(dialled.stages[0].phases[0].manner == .curledTongue)
        #expect(dialled.preparation == curated.preparation)
        #expect(dialled.preparation != nil)
        // And the words that hang off it survive with it.
        #expect(SessionTimeline(technique: dialled).beats[0].hint.line
            == "Through a curled tongue")
    }

    /// The how-to rows the exercise page prints, where the mechanic replaces the
    /// passage rather than being appended to it.
    ///
    /// The final assertion is the one that catches somebody reintroducing the
    /// interpolation `Manner.instruction(for:)` exists to refuse: a clause bolted
    /// onto a sentence is English word order no translator can fix from outside.
    @Test("A shaped breath's step names the shape, not the passage")
    func aShapedBreathsStepNamesTheShape() {
        #expect(technique("cooling-breath").stages[0].steps.map(\.instruction) == [
            "Breathe in through a curled tongue",
            "Breathe out",
        ])
        #expect(technique("pursed-lip-breathing").stages[0].steps.map(\.instruction) == [
            "Breathe in",
            "Breathe out through pursed lips",
        ])
        #expect(technique("humming-breath").stages[0].steps.map(\.instruction) == [
            "Breathe in",
            "Breathe out, humming all the way",
        ])

        for technique in SeededCatalogue.techniques {
            for stage in technique.stages {
                #expect(stage.steps.allSatisfy { !$0.instruction.contains(", through") })
            }
        }
    }

    /// Empty means absent, said once by the type rather than by each decoder.
    @Test("An empty curated string arrives as nothing at all")
    func emptyCollapsesToNil() {
        let blank = Technique(
            id: "x",
            slug: "x",
            name: "X",
            summary: "",
            goal: .calm,
            stages: technique("box-breathing").stages,
            recommendedRounds: 1,
            mechanism: "",
            evidence: "",
            safetyNote: ""
        )

        #expect(blank.mechanism == nil)
        #expect(blank.evidence == nil)
        #expect(blank.safetyNote == nil)
    }

    /// A curated exercise explains its mechanism, and its summary is not read
    /// twice on one screen — the regression the closing note exists to prevent.
    @Test("A curated exercise explains why it works")
    func aCuratedExerciseClosesOnItsMechanism() {
        let box = technique("box-breathing")

        #expect(box.closingNote == box.mechanism)
        #expect(box.closingNote != box.summary)
    }

    /// Nobody asks an author to assert physiology, so an exercise somebody wrote
    /// has only the description they typed, and its screen explains that.
    @Test("An exercise somebody wrote uses the description they typed")
    func anAuthoredExerciseClosesOnItsSummary() {
        let authored = authoredTechnique(summary: "For winding down after work.")

        #expect(authored.mechanism == nil)
        #expect(authored.closingNote == "For winding down after work.")
    }

    /// The description is optional in the composer, and a blank one produces no
    /// topic rather than an empty paragraph.
    @Test("An exercise written without a description explains nothing")
    func anAuthoredExerciseWithoutADescriptionClosesOnNothing() {
        #expect(authoredTechnique(summary: "").closingNote == nil)
    }

    private func authoredTechnique(summary: String) -> Technique {
        Technique(
            id: "x",
            slug: "x",
            name: "X",
            summary: summary,
            goal: .calm,
            stages: technique("box-breathing").stages,
            recommendedRounds: 1,
            origin: .personal
        )
    }
}
