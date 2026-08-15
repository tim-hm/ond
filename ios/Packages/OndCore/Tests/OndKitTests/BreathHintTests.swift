import Foundation
@testable import OndKit
import Testing

/// The line under the cue: which rung answers, and what it says.
///
/// Over the seeded catalogue rather than fixtures, on `SeededCatalogue`'s
/// reasoning: "the cooling breath says the tongue rather than the mouth" is only
/// worth asserting about the exercise the app actually ships.
@Suite("The hint under the cue")
struct BreathHintTests {
    private func timeline(_ slug: String) -> SessionTimeline {
        SeededCatalogue.timeline(slug)
    }

    /// The rung that exists at all because a passage was the true answer to a
    /// question nobody was asking. "Mouth" is not wrong about the cooling
    /// breath; it is just never the half worth the line.
    @Test("A manner outranks the passage underneath it")
    func aMannerOutranksItsPassage() {
        let opening = timeline("cooling-breath").beats[0]

        #expect(opening.manner == .curledTongue)
        #expect(opening.passage == .mouth)
        #expect(opening.hint.line == "Through a curled tongue")
        #expect(opening.hint.glance == "Curled tongue")
        // The cue above it is untouched: the shape belongs on the second line,
        // and "Breathe in" is what a glance through half-closed eyes needs.
        #expect(opening.instruction == "Breathe in")
    }

    @Test("The shaped exhales say what they are")
    func theShapedExhalesSayWhatTheyAre() {
        #expect(timeline("pursed-lip-breathing").beats[1].hint.line == "Through pursed lips")
        // A nasal exhale, so nothing but the manner would have said anything at
        // all — the hum was invisible on every surface before this.
        let hum = timeline("humming-breath").beats[1]
        #expect(hum.passage == .nose)
        #expect(hum.hint.line == "Hum all the way out")
    }

    /// The rung that was already working, unchanged — and the reason the manner
    /// had to be a rung above rather than a replacement for it.
    @Test("A passage still answers where nothing shapes the breath")
    func aPassageStillAnswers() {
        #expect(timeline("alternate-nostril").beats.prefix(4).map(\.hint.line) == [
            "Left nostril",
            "Right nostril",
            "Right nostril",
            "Left nostril",
        ])
    }

    /// The order of the phases still says which hold you are in; this says it
    /// on a line that is drawn anyway. See `PhaseKind.standaloneTitle`, whose
    /// argument this does not overturn.
    @Test("A hold says which hold it is")
    func aHoldSaysWhichHoldItIs() {
        #expect(timeline("box-breathing").beats.prefix(4).map(\.hint.line) == [
            nil,
            "Lungs full",
            nil,
            "Lungs empty",
        ])
    }

    /// The most valuable assertion here, and the one that stops somebody merging
    /// the two fast thresholds.
    ///
    /// The sigh is what separates them — `theTwoThresholdsDisagree` states that
    /// on the stage, and this states the consequence on the beats: reading the
    /// pace off `isFastRhythm` would print "Fast and even" over a sigh, which is
    /// both wrong and the opposite of what that exercise is for.
    @Test("The pace is read off the cycle, not off the phase")
    func thePaceIsReadOffTheCycle() {
        #expect(timeline("bellows-breath").beats.allSatisfy { $0.hint.line == BreathHint.fastLine })
        #expect(timeline("physiological-sigh").beats
            .allSatisfy { $0.hint.line != BreathHint.fastLine })
    }

    /// The pace ranks last because it is a fact about the stage: a shaped or
    /// placed breath inside a fast stage still says its own thing first.
    @Test("The pace does not outrank what the phase says about itself")
    func thePaceRanksLast() {
        let hint = BreathHint(
            manner: .curledTongue,
            breath: .inhale(through: .mouth),
            breathesFast: true
        )
        #expect(hint.line == "Through a curled tongue")

        #expect(BreathHint(manner: nil, breath: .holdOut, breathesFast: true).line == "Lungs empty")
    }

    @Test("An exercise with nothing to add says nothing")
    func anExerciseWithNothingToAddSaysNothing() {
        #expect(timeline("coherent-breathing").beats.allSatisfy { $0.hint.line == nil })
        #expect(timeline("extended-exhale").beats.allSatisfy { $0.hint.line == nil })
    }

    /// The claim that lets `glance` fall through instead of carrying a second
    /// spelling of every rung: only the manner is long enough to need one.
    @Test("Only a manner has a second, shorter form")
    func onlyAMannerHasAShorterForm() {
        for slug in ["alternate-nostril", "box-breathing", "bellows-breath"] {
            for beat in timeline(slug).beats {
                #expect(beat.hint.glance == beat.hint.line)
            }
        }

        for manner in Manner.allCases {
            #expect(!manner.hint.isEmpty)
            #expect(!manner.glanceHint.isEmpty)
            #expect(manner.glanceHint.count < manner.hint.count)
        }
    }

    /// `hintsAnyBeat` reserves the line from `line`, and the watch draws
    /// `glance` into it — so a beat where one is nil and the other is not would
    /// give the wrist a reserved blank or an unreserved word. True by
    /// construction today, and asserted because nothing else says so.
    @Test("A beat hints in both forms or in neither")
    func theTwoFormsAgreeOnSilence() {
        for technique in SeededCatalogue.techniques {
            for beat in SessionTimeline(technique: technique).beats {
                #expect((beat.hint.line == nil) == (beat.hint.glance == nil))
            }
        }
    }

    /// The two hold spellings, written down side by side so that retuning one
    /// without the other shows both literals in the diff — which is the whole of
    /// what keeps `lungsState` and `standaloneTitle` from drifting.
    @Test("The two ways of naming a hold agree")
    func theTwoWaysOfNamingAHoldAgree() {
        #expect(PhaseKind.holdIn.lungsState == "Lungs full")
        #expect(PhaseKind.holdIn.standaloneTitle == "Hold, lungs full")
        #expect(PhaseKind.holdOut.lungsState == "Lungs empty")
        #expect(PhaseKind.holdOut.standaloneTitle == "Hold, lungs empty")
        #expect(PhaseKind.inhale.lungsState == nil)
        #expect(PhaseKind.exhale.lungsState == nil)
    }
}

/// The one number this app holds a second copy of, and the tripwire that copy
/// needs.
@Suite("The mirrored physiology")
struct PhysiologyTests {
    /// `crates/physiology` exists to abolish duplicated copies of these numbers,
    /// and Swift cannot take that dependency — so the seed exports the threshold
    /// and this is what compares them. Without this assertion the constant is
    /// exactly the unwatched drift that crate was created to end.
    @Test("The threshold agrees with the one the seed exported")
    func theThresholdAgreesWithTheSeed() {
        let bundled = CatalogueExport.bundled
        // First that anything was read at all. `.empty` defaults this field to
        // the very constant under test, so a build whose resource failed to
        // decode would satisfy the comparison below while comparing the
        // compiled value against itself — the one way this test can pass by
        // saying nothing.
        #expect(!bundled.techniques.isEmpty)
        #expect(bundled.exportedFastBreathingCycle == Physiology.fastBreathingCycle)
    }

    /// Which side of the line the boundary falls on, from both directions.
    ///
    /// Mirroring `breathes_fast` means mirroring the comparison as well as the
    /// number: a rule that quietly stopped applying at its own threshold would
    /// look identical to one that worked.
    @Test("Four seconds a cycle is the resting rate, not a fast one")
    func theThresholdIsInclusiveOfTheSlowSide() {
        #expect(Physiology.breathesFast(.milliseconds(3999)))
        #expect(!Physiology.breathesFast(.seconds(4)))
        #expect(!Physiology.breathesFast(.milliseconds(4001)))
    }

    /// The two thresholds this app now holds are different rules, and the sigh
    /// is the entry that proves it rather than a hypothetical.
    @Test("The legibility threshold and the physiology one disagree")
    func theTwoThresholdsDisagree() {
        let sigh = SeededCatalogue.technique("physiological-sigh").stages[0]
        #expect(sigh.isFastRhythm)
        #expect(!sigh.breathesFast)

        let bellows = SeededCatalogue.technique("bellows-breath").stages[0]
        #expect(bellows.isFastRhythm)
        #expect(bellows.breathesFast)
    }
}
