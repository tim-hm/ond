import Foundation
@testable import OndKit
import Testing

/// What Home leads with, and the rule that nothing on it appears twice.
///
/// The lead rules are `HomeDial`'s, ported whole when the dial was deleted: a
/// person who has breathed nothing meets Start here, everybody else meets the
/// protocol that fits the hour, and two fallbacks behind that keep a device with
/// no occasions answering.
@Suite("Home's shelf")
struct HomeShelfTests {
    // MARK: what Home leads with

    @Test("Somebody who has breathed nothing leads with the first rung of Start here")
    func firstRunLeadsWithTheProgression() {
        let suggested = ShelfFixtures.shelf().suggested

        #expect(suggested?.band == .startHere)
        #expect(suggested?.title == SeededCatalogue.technique("box-breathing").name)
    }

    @Test("Somebody with history leads with the protocol the hour fits")
    func theHourPicksTheOccasion() {
        // 23:00 is `sleep` by `HomeSuggestion`, and one protocol borrows it.
        let suggested = ShelfFixtures.shelf(
            history: [HomeFixtures.session("box-breathing")],
            hour: 23
        ).suggested

        #expect(suggested?.title == "Winding down")
        #expect(suggested?.goal == .sleep)
        // The prescription travels with it, which is the whole reason a protocol
        // beats the plain exercise here: the same technique, at the length and in
        // the register the moment asked for.
        #expect(suggested?.occasionSlug == "winding-down")
        #expect(suggested?.duration == .seconds(300))
    }

    @Test("The rung led with advances as each one is breathed")
    func theProgressionIsReadFromTheirOwnHistory() {
        // 08:00 is `energy`, which no protocol here borrows, so the lead is the
        // progression's.
        let two = [
            HomeFixtures.session("box-breathing"),
            HomeFixtures.session("physiological-sigh"),
        ]

        #expect(ShelfFixtures.shelf(history: two, hour: 8).suggested?.technique
            .slug == "extended-exhale")
        #expect(ShelfFixtures.shelf(history: [], hour: 8).suggested?.technique
            .slug == "box-breathing")
    }

    /// The regression the review found: `JourneyModel.history` is newest first,
    /// and the rule read "last used" off the array's order rather than off the
    /// dates — so a returning person was offered the first thing they ever
    /// breathed.
    @Test("With every rung breathed, the fallback is the last exercise used for the hour's goal")
    func theFallbackIsTheLastUsedRatherThanTheFirst() {
        let breathed = ShelfFixtures.progression.map { HomeFixtures.session($0.techniqueSlug) }
        // Both are `focus`, which 14:00 occasions to and no protocol here borrows.
        let focused = [
            HomeFixtures.session("long-box-breathing", at: .now.addingTimeInterval(-7200)),
            HomeFixtures.session("alternate-nostril", at: .now.addingTimeInterval(-60)),
        ]

        let suggested = ShelfFixtures.shelf(history: breathed + focused).suggested

        #expect(suggested?.technique.slug == "alternate-nostril")
        #expect(suggested?.band == .everything)
    }

    @Test("With no occasions at all, the lead is still the hour's own suggestion")
    func aDeviceWithNoRoutesStillLeadsWithSomething() {
        let suggested = ShelfFixtures.shelf(
            history: [HomeFixtures.session("box-breathing")],
            hour: 23,
            occasions: .none
        ).suggested

        #expect(suggested?.band == .everything)
        #expect(suggested?.goal == .sleep)
    }

    @Test("An empty catalogue leads with nothing rather than something invented")
    func anEmptyCatalogueLeadsWithNothing() {
        let shelf = HomeShelf(
            techniques: [], occasions: .none, history: [], starred: [], hour: 14
        )

        #expect(shelf.suggested == nil)
        #expect(shelf.lastRun == nil)
        #expect(shelf.starred.isEmpty)
    }

    /// A length stated is a length the tap owes, and the dials this person set
    /// have to reach the row rather than only the session.
    @Test("A dialled exercise is suggested at the length this person set")
    func theSuggestionCarriesTheirOwnDials() {
        let nostril = SeededCatalogue.technique("alternate-nostril")
        var longer = nostril.curatedOverrides
        longer.rounds = nostril.recommendedRounds + 3

        let breathed = ShelfFixtures.progression.map { HomeFixtures.session($0.techniqueSlug) }
        let suggested = ShelfFixtures.shelf(
            history: breathed + [HomeFixtures.session("alternate-nostril")],
            dialled: [nostril.slug: longer]
        ).suggested

        #expect(suggested?.dialled == nostril.dialled(with: longer))
        #expect(suggested?.duration == nostril.dialled(with: longer).plannedDuration)
    }

    /// The two immediate actions already carry their own star affordances, so a
    /// star should not create another copy directly beneath them.
    @Test("Starred does not repeat either action card")
    func starredDoesNotRepeatActions() {
        let history = [HomeFixtures.session("extended-exhale")]
        let shelf = ShelfFixtures.shelf(
            starred: ["occasions/winding-down", "everything/extended-exhale"],
            history: history,
            hour: 23
        )

        #expect(shelf.suggested?.id == "occasions/winding-down")
        #expect(shelf.lastRun?.stop.id == "everything/extended-exhale")
        #expect(shelf.starred.isEmpty)
    }

    @Test("Repeat remains available when suggestion names the same exercise")
    func repeatCanMatchSuggestion() {
        // 08:00 occasions to no protocol, and every rung is breathed, so the lead
        // falls through to the last `energy` exercise used — which is also the
        // most recent session.
        let breathed = ShelfFixtures.progression.enumerated().map { offset, step in
            HomeFixtures.session(
                step.techniqueSlug,
                at: .now.addingTimeInterval(TimeInterval(-3600 * (offset + 2)))
            )
        }
        let shelf = ShelfFixtures.shelf(
            history: breathed + [HomeFixtures.session("bellows-breath", at: .now)],
            hour: 8
        )

        #expect(shelf.suggested?.technique.slug == "bellows-breath")
        #expect(shelf.lastRun?.stop.technique.slug == "bellows-breath")
    }
}
