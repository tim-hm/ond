import Foundation
import OndKit
import Testing

/// Starting your own exercise from a curated one.
///
/// The copy is an ordinary authored exercise that happens to open pre-filled —
/// no lineage is kept and nothing on the draft points back at the catalogue.
/// What these pin is that the content survives the trip and that the trip is
/// offered only where it can be made without quietly rewriting the exercise.
@Suite("Making your own version of a curated exercise")
struct TechniqueCopyTests {
    /// The limits the server would derive from this catalogue: the shared
    /// fixture's ceilings, with the phase ranges derived from the seed rather
    /// than written down.
    ///
    /// `user_technique/repository.rs` takes the widest interval the seeded
    /// phases put each kind in, ignoring open-ended stages — "including it would
    /// let somebody author a minute-long breath-hold on a clock". Ranges typed
    /// into a fixture would pass while the seed moved underneath them, which is
    /// the drift these tests exist to catch; the ceilings around them are fixed
    /// server-side and are the shared fixture's to state once.
    private static var derivedLimits: AuthoringLimits {
        var spans: [PhaseKind: ClosedRange<Duration>] = [:]

        for technique in SeededCatalogue.techniques {
            for stage in technique.stages where !stage.openEnded {
                for phase in stage.phases {
                    let range = phase.range
                    spans[phase.kind] = spans[phase.kind].map { known in
                        min(known.lowerBound, range.lowerBound)
                            ... max(known.upperBound, range.upperBound)
                    } ?? range
                }
            }
        }

        return AuthoringLimits(
            phases: spans.map { PhaseLimit(kind: $0.key, range: $0.value) },
            maxNameChars: limits.maxNameChars,
            maxSummaryChars: limits.maxSummaryChars,
            maxStages: limits.maxStages,
            maxPhasesPerStage: limits.maxPhasesPerStage,
            cycleRange: limits.cycleRange,
            roundRange: limits.roundRange,
            maxTechniques: limits.maxTechniques
        )
    }

    /// Every curated exercise a copy is offered for must survive the trip
    /// untouched, because the composer shows the clamped draft and the person
    /// reads those numbers as what they are about to get.
    ///
    /// The failure this catches is a seed edit rather than a code one: widen a
    /// phase past the range its own kind spans elsewhere, or add a fifth stage,
    /// and copying that exercise silently returns something else. Asserted over
    /// the whole catalogue so a new technique is covered the day it lands.
    @Test("Copying any curated exercise changes nothing about it")
    func everyCopyableExerciseSurvivesTheTrip() {
        let limits = Self.derivedLimits

        for technique in SeededCatalogue.techniques where technique.isCopyable {
            let copied = TechniqueDraft(copying: technique)

            #expect(
                limits.clamping(copied) == copied,
                "`\(technique.slug)` does not survive being copied unchanged"
            )
        }
    }

    /// The content crosses and the identity does not — which is the whole reason
    /// one initialiser serves both Edit and this.
    @Test("A copy carries the words and the rhythm, and nothing that names the original")
    func aCopyCarriesContentOnly() throws {
        let box = SeededCatalogue.technique("box-breathing")
        let copied = TechniqueDraft(copying: box)

        #expect(copied.name == box.name)
        #expect(copied.summary == box.summary)
        #expect(copied.goal == box.goal)
        #expect(copied.rounds == box.recommendedRounds)

        let stage = try #require(copied.stages.first)
        #expect(copied.stages.count == box.stages.count)
        #expect(stage.cycles == box.stages[0].cycles)
        #expect(stage.phases.map(\.duration) == box.stages[0].phases.map(\.duration))
        #expect(stage.phases.map(\.movement) == box.stages[0].phases.map { Movement($0.breath) })
    }

    /// The one exercise the copy is withheld from, asserted on the property that
    /// withholds it rather than on the reason behind it — so a screen that offers
    /// a copy is offering exactly what this covers.
    ///
    /// A retention ends when the person does. Authoring cannot express that at
    /// all, so a copy would arrive with the defining feature of the protocol
    /// rewritten as a timed hold.
    @Test("The only curated exercise that cannot be copied is the one with a retention")
    func onlyTheRetentionIsWithheld() {
        let withheld = SeededCatalogue.techniques.filter { !$0.isCopyable }

        #expect(withheld.map(\.slug) == ["wim-hof-rounds"])
    }

    /// Somebody's own exercise is edited, never copied: it is already theirs, and
    /// the copy of a copy is a list nobody can read.
    ///
    /// The subject is a saved copy of a curated exercise, so the only thing that
    /// changed between `isCopyable` and `!isCopyable` is whose it is.
    @Test("An authored exercise is not offered a copy of itself")
    func anAuthoredExerciseIsNotCopyable() {
        let box = SeededCatalogue.technique("box-breathing")
        let mine = stored(TechniqueDraft(copying: box), id: "1")

        #expect(box.isCopyable)
        #expect(!mine.isCopyable)
    }
}
