import Foundation
@testable import OndKit
import Testing

/// The sentences an exercise's own screen says about it, over the catalogue they
/// describe.
///
/// These lived in the app target until the words moved here, which is why they had
/// no tests: `ios/Ond/` has no test bundle, so four dose phrasings and a
/// nose-is-silent exception were curation rules over nine seeded exercises that
/// nothing checked.
@Suite("What an exercise's screen says about it")
struct TechniqueWordsTests {
    private func technique(_ slug: String) -> Technique {
        SeededCatalogue.technique(slug)
    }

    /// The rule the detail screen's two halves share, and the reason
    /// `opening` and `practiceSummary` live on the type rather than in the
    /// views: whichever way the mechanism question goes, the summary appears on
    /// the screen exactly once.
    @Test("The opening and the caption between them say the summary exactly once")
    func theSummaryAppearsExactlyOnce() {
        let curated = technique("box-breathing")
        #expect(curated.opening == curated.mechanism)
        #expect(curated.practiceSummary == curated.summary)

        let authored = Technique(
            id: "x",
            slug: "x",
            name: "X",
            summary: "My own exercise.",
            goal: .calm,
            stages: curated.stages,
            recommendedRounds: 1
        )
        #expect(authored.opening == authored.summary)
        #expect(authored.practiceSummary == nil)
    }

    /// The plain case, and the one the copy was written against.
    @Test("A cyclic exercise states its cycles, its length, and that the count is not the point")
    func aCyclicExerciseStatesItsDose() {
        #expect(
            technique("box-breathing").doseDescription
                == "8 cycles, about 2 minutes. However many you do is the practice."
        )
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
        #expect(technique("box-breathing").plannedDuration.spelled == "2 minutes")
        #expect(technique("box-breathing").plannedDuration.glanceable == "2 min")
        #expect(technique("physiological-sigh").plannedDuration.spelled == "22 seconds")
    }

    /// The rule `Passage.hint` states, applied to a whole exercise: the nose is what
    /// the foundations teach and what most of the catalogue does throughout, so
    /// naming it on every screen is the noise that stops the other ones being read.
    @Test("Breathing through the nose throughout is left unsaid")
    func theNoseGoesUnmentioned() {
        #expect(technique("box-breathing").passageNote == nil)
        #expect(technique("coherent-breathing").passageNote == nil)
    }

    /// The one seeded exercise that changes passage mid-cycle, and the reason the
    /// sentence exists at all: the figure marks a nostril with a letter and a mouth
    /// with nothing, so this is said here or nowhere.
    @Test("An exercise that leaves through the mouth says so")
    func aMouthExhaleIsNamed() {
        #expect(
            technique("physiological-sigh").passageNote
                == "In through your nose, out through your mouth."
        )
    }

    /// Alternate-nostril breathing is deliberately silent rather than wrong. One
    /// sentence cannot say "alternating, and which hand closes which", and its own
    /// summary already says it properly.
    @Test("Alternating nostrils is left to the exercise's own summary")
    func alternatingNostrilsIsNotReducedToASentence() {
        #expect(technique("alternate-nostril").passageNote == nil)
        #expect(technique("alternate-nostril").summary.contains("Thumb closes the right nostril"))
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
            phaseDurationsMs: [[5000, 5000, 5000, 5000]],
            stageCycles: [4],
            rounds: 1
        ))

        #expect(dialled.stages.first?.cycles == 4)
        #expect(dialled.mechanism == curated.mechanism)
        #expect(dialled.mechanism != nil)
        #expect(dialled.summary == curated.summary)
        #expect(dialled.safetyNote == curated.safetyNote)
        #expect(dialled.requires == curated.requires)
        #expect(dialled.origin == curated.origin)
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
            safetyNote: ""
        )

        #expect(blank.mechanism == nil)
        #expect(blank.safetyNote == nil)
    }
}
