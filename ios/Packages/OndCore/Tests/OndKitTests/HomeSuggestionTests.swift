import Foundation
import OndKit
import Testing

/// The home screen's rules are trivial to eyeball and easy to get quietly
/// wrong: an off-by-one hour boundary points the aim at bellows breath at
/// bedtime, and a goal the catalogue stopped serving must still resolve to
/// something Begin can start.
@Suite("Choosing what the home screen leads with")
struct HomeSuggestionTests {
    private func technique(slug: String, goal: TechniqueGoal) -> Technique {
        Technique(
            id: slug,
            slug: slug,
            name: slug,
            summary: "",
            goal: goal,
            stages: [Stage(phases: [Phase(kind: .inhale, duration: .seconds(4))], cycles: 1)],
            recommendedRounds: 1
        )
    }

    private func session(slug: String, at seconds: TimeInterval = 0) -> SessionRecord {
        SessionRecord(
            techniqueSlug: slug,
            startedAt: Date(timeIntervalSince1970: seconds),
            duration: .seconds(60),
            cyclesCompleted: 1,
            breathCount: 1,
            completed: true
        )
    }

    private var catalogue: [Technique] {
        [
            technique(slug: "box", goal: .calm),
            technique(slug: "478", goal: .sleep),
            technique(slug: "bellows", goal: .energy),
            technique(slug: "coherent", goal: .focus),
        ]
    }

    @Test("Home offers what this person last used towards the goal")
    func prefersTheirOwnTechnique() {
        let catalogue = catalogue + [technique(slug: "extended", goal: .sleep)]

        let chosen = HomeSuggestion.technique(
            for: .sleep,
            techniques: catalogue,
            history: [session(slug: "extended"), session(slug: "bellows")]
        )

        #expect(chosen?.slug == "extended", "the bellows session is for another goal")
    }

    /// The regression this shipped with for one commit. The rule was written as
    /// `history.reversed().first`, which reads "last" off the array's order, and
    /// the caller that replaced the original hands over `JourneyModel.history` —
    /// newest first. Home then offered the first thing anybody ever breathed.
    ///
    /// Both orders, from one set of records, so the claim is that the dates
    /// decide rather than that one caller happens to sort the way this expects.
    @Test("Which session was last is read off the dates, not the array's order")
    func theLatestSessionIsFoundInAnyOrder() {
        let catalogue = catalogue + [technique(slug: "extended", goal: .sleep)]
        let oldest = session(slug: "478", at: 0)
        let newest = session(slug: "extended", at: 10000)

        for history in [[oldest, newest], [newest, oldest]] {
            #expect(
                HomeSuggestion.technique(for: .sleep, techniques: catalogue, history: history)?
                    .slug == "extended"
            )
        }
    }

    @Test("With no history for the goal, the catalogue's first for it wins")
    func fallsBackToTheCatalogue() {
        let chosen = HomeSuggestion.technique(
            for: .sleep,
            techniques: catalogue,
            history: [session(slug: "box")]
        )

        #expect(chosen?.slug == "478")
    }

    /// Home only offers goals the catalogue can serve, but a technique
    /// retired between load and tap must still start something rather than
    /// leaving Begin pointing at nothing.
    @Test("A goal the catalogue cannot serve still yields a technique")
    func unservedGoalStillStarts() {
        let sleepless = [technique(slug: "box", goal: .calm)]

        #expect(
            HomeSuggestion.technique(for: .sleep, techniques: sleepless, history: [])?.slug == "box"
        )
        #expect(HomeSuggestion.technique(for: .sleep, techniques: [], history: []) == nil)
    }

    /// The home screen's aims, the techniques list's sections, and anything
    /// else built from a catalogue read this one order. A catalogue that came
    /// back sorted differently must not move sleep out from under a thumb that
    /// has learned where it is.
    @Test("Present goals come back in the enum's order, not the catalogue's")
    func presentGoalsFollowTheEnum() {
        let shuffled = [
            technique(slug: "478", goal: .sleep),
            technique(slug: "bellows", goal: .energy),
            technique(slug: "box", goal: .calm),
        ]

        #expect(TechniqueGoal.present(in: shuffled) == [.calm, .sleep, .energy])
        #expect(TechniqueGoal.present(in: []).isEmpty)
    }
}
