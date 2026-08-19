import Foundation
@testable import OndKit
import Testing

/// What Home's button starts and what its sheet offers beside it.
@Suite("Home's offer")
struct HomeOfferTests {
    private func slugs(_ offer: HomeOffer) -> [String] {
        offer.rows.map(\.technique.slug)
    }

    // MARK: the default

    @Test("With no choice and no goal, the resting pace leads")
    func theRestingPaceIsTheFallback() throws {
        let offer = try ShelfFixtures.offer()

        #expect(offer.lead.technique.slug == "coherent-breathing")
        #expect(offer.rows.count == HomeOffer.capacity)
        #expect(offer.minutes == HomeOffer.defaultMinutes)
    }

    @Test("The first onboarding goal implies the default")
    func theGoalImpliesTheDefault() throws {
        let offer = try ShelfFixtures.offer(goals: [.sleep, .energy])

        #expect(offer.lead.technique.goal == .sleep)
        #expect(slugs(offer).prefix(2).map { SeededCatalogue.technique($0).goal } == [
            .sleep,
            .energy,
        ])
    }

    @Test("A choice leads whatever the goals say")
    func theChoiceLeads() throws {
        let offer = try ShelfFixtures.offer(
            goals: [.sleep],
            choice: HomeChoice(slug: ShelfFixtures.unrouted.slug, minutes: 10)
        )

        #expect(offer.lead.technique.slug == ShelfFixtures.unrouted.slug)
        #expect(offer.minutes == 10)
    }

    @Test("A choice naming an exercise the catalogue no longer holds is ignored")
    func anUnresolvableChoiceFallsBack() throws {
        let offer = try ShelfFixtures.offer(
            goals: [.sleep],
            choice: HomeChoice(slug: "gone", minutes: 3)
        )

        #expect(offer.lead.technique.goal == .sleep)
        #expect(offer.minutes == 3, "the length still stands; only the exercise was lost")
    }

    @Test("A choice can name an exercise this person wrote")
    func aChoiceResolvesInTheAuthoredList() throws {
        let offer = try ShelfFixtures.offer(
            choice: HomeChoice(slug: "mine", minutes: 5),
            authored: [ShelfFixtures.authored]
        )

        #expect(offer.lead.id == "yours/mine")
    }

    // MARK: the rows

    @Test("Stars sit between the default and the goals' recommendations")
    func starsFollowTheDefault() throws {
        let starred = DialStop.id(of: ShelfFixtures.unrouted)
        let offer = try ShelfFixtures.offer(starred: [starred], goals: [.sleep, .energy])

        #expect(slugs(offer)[1] == ShelfFixtures.unrouted.slug)
        #expect(offer.rows[2].goal == .energy)
    }

    @Test("A star under any exercise band counts, and an occasion star does not", arguments: [
        ("startHere/humming-breath", true),
        ("everything/humming-breath", true),
        ("occasions/winding-down", false),
    ])
    func starsResolveByExercise(_ id: DialStop.ID, _ reaches: Bool) throws {
        let offer = try ShelfFixtures.offer(starred: [id])

        #expect(slugs(offer).contains("humming-breath") == reaches)
        #expect(offer.rows.allSatisfy { $0.occasionSlug == nil })
    }

    @Test("An authored star leads the catalogue's stars")
    func authoredStarsComeFirst() throws {
        let offer = try ShelfFixtures.offer(
            starred: [
                DialStop.id(of: ShelfFixtures.authored),
                DialStop.id(of: ShelfFixtures.unrouted),
            ],
            authored: [ShelfFixtures.authored]
        )

        #expect(offer.rows.map(\.id) == [
            "everything/coherent-breathing", "yours/mine", "everything/humming-breath",
        ])
    }

    @Test("Never more than three rows, and never the same exercise twice")
    func threeRowsAtMost() throws {
        let starred = Set(SeededCatalogue.techniques.map(DialStop.id(of:)))
        let offer = try ShelfFixtures.offer(
            starred: starred,
            goals: TechniqueGoal.allCases,
            choice: HomeChoice(slug: "box-breathing", minutes: 5)
        )

        #expect(offer.rows.count == HomeOffer.capacity)
        #expect(Set(slugs(offer)).count == HomeOffer.capacity)
        #expect(slugs(offer).first == "box-breathing")
    }

    @Test("A goal's recommendation is the exercise last breathed towards it")
    func goalsRememberWhatWasBreathed() throws {
        let history = [HomeFixtures.session("cyclic-sighing")]
        let offer = try ShelfFixtures.offer(goals: [.calm], history: history)

        #expect(offer.lead.technique.slug == "cyclic-sighing")
    }

    // MARK: the lead's length

    @Test("The lead is fitted to the chosen length")
    func theLeadIsFitted() throws {
        let offer = try ShelfFixtures.offer(choice: HomeChoice(slug: "box-breathing", minutes: 3))

        #expect(offer.isFittable)
        #expect(
            offer.lead.duration == .seconds(176),
            "eleven sixteen-second cycles is the nearest whole count"
        )
    }

    @Test("The lead plays the person's own dials, fitted")
    func theLeadKeepsTheDials() throws {
        let box = SeededCatalogue.technique("box-breathing")
        var slower = box.curatedOverrides
        slower.stages[0].phaseDurationsMs = [5000, 5000, 5000, 5000]
        let offer = try ShelfFixtures.offer(
            choice: HomeChoice(slug: "box-breathing", minutes: 5),
            dialled: ["box-breathing": slower]
        )

        #expect(offer.lead.dialled.stages.first?.cycleDuration == .seconds(20))
        #expect(offer.lead.duration == .seconds(300))
        #expect(
            offer.rows[0].dialled.stages.first?.cycleDuration == .seconds(20),
            "the row shows the same breath"
        )
    }

    @Test("A staged exercise keeps its curated length and is not fittable")
    func aStagedLeadIsNotFitted() throws {
        let offer = try ShelfFixtures.offer(choice: HomeChoice(slug: "wim-hof-rounds", minutes: 3))

        #expect(!offer.isFittable)
        #expect(offer.lead.duration == SeededCatalogue.technique("wim-hof-rounds").plannedDuration)
    }

    @Test("An empty catalogue offers nothing")
    func anEmptyCatalogueIsNil() {
        #expect(HomeOffer(techniques: [], choice: nil) == nil)
    }
}
