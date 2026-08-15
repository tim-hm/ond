import Foundation
@testable import OndKit
import Testing

/// What a star resolves to on Home's shelf, and what the last session offers
/// again.
///
/// Its own suite beside the lead's, because the questions are different: one is
/// about what the app chooses and this is about what somebody chose and what
/// they last did.
@Suite("Home's shelf, starred and rerun")
struct HomeShelfStarsTests {
    // MARK: what a star resolves to

    /// The path a star made two tabs away has to survive. Nothing occasions to most
    /// of the catalogue — no seeded protocol borrows `energy` or `focus` — so an
    /// exercise found on the Exercises tab could be breathed daily and never
    /// reach Home without this.
    @Test("A star made on an exercise's own screen becomes a shelf row")
    func aStarredCatalogueExerciseIsShelved() {
        let starred = DialStop.id(of: ShelfFixtures.unrouted)

        #expect(ShelfFixtures.shelf(starred: [starred]).starred.map(\.id) == [starred])
    }

    @Test("A star resolves in whichever band it names", arguments: [
        "occasions/winding-down",
        "startHere/physiological-sigh",
        "everything/coherent-breathing",
    ])
    func everyBandAnswersAStar(_ id: DialStop.ID) {
        #expect(ShelfFixtures.shelf(starred: [id]).starred.map(\.id) == [id])
    }

    @Test("An authored exercise is starred in its own band")
    func theAuthoredBandAnswersAStar() {
        let starred = DialStop.id(of: ShelfFixtures.authored)

        #expect(starred == "yours/mine")
        #expect(
            ShelfFixtures.shelf(starred: [starred], authored: [ShelfFixtures.authored]).starred
                .map(\.id) == [starred]
        )
    }

    /// Dial order rather than star order, which is why `StarredStopStore` holds
    /// a set: two stars stay in the order Home would have shown them anyway.
    @Test("Stars keep dial order, whatever order they were set in")
    func starsKeepDialOrder() {
        let ids: Set<DialStop.ID> = [
            "everything/coherent-breathing",
            "yours/mine",
            "occasions/winding-down",
            "startHere/physiological-sigh",
        ]

        #expect(ShelfFixtures.shelf(starred: ids, authored: [ShelfFixtures.authored]).starred
            .map(\.id) == [
                "occasions/winding-down",
                "startHere/physiological-sigh",
                "yours/mine",
                "everything/coherent-breathing",
            ])
    }

    /// No star migration was run, so the keyspace still holds ids for stops the
    /// occasions no longer send. They pin nothing, silently — which is the right
    /// answer for a key naming something that no longer exists.
    @Test("An id nothing resolves pins nothing")
    func inertIdsPinNothing() {
        let shelf = ShelfFixtures.shelf(starred: [
            "occasions/a-moment-nobody-seeds",
            "startHere/an-exercise-nobody-ships",
            "yours/box-breathing",
        ])

        #expect(shelf.starred.isEmpty)
    }

    /// A star is never subtractive: an empty set is an empty shelf and not the
    /// catalogue, because Home leaves browsing to the tab two icons away.
    @Test("No stars is an empty shelf")
    func noStarsIsAnEmptyShelf() {
        #expect(ShelfFixtures.shelf().starred.isEmpty)
        #expect(ShelfFixtures.shelf(occasions: .none).starred.isEmpty)
    }

    // MARK: the last thing breathed

    @Test("Nothing breathed is nothing to pick up")
    func noHistoryIsNoRerun() {
        #expect(ShelfFixtures.shelf().lastRun == nil)
    }

    @Test("The most recent session is the one offered again")
    func theRerunIsTheMostRecent() {
        let older = HomeFixtures.session("box-breathing", at: .now.addingTimeInterval(-7200))
        let newer = HomeFixtures.session("coherent-breathing", at: .now.addingTimeInterval(-60))

        // Newest first, the order `JourneyModel` hands it over in, so a rule
        // reading the array's order rather than the dates fails here.
        let lastRun = ShelfFixtures.shelf(history: [newer, older]).lastRun

        #expect(lastRun?.stop.technique.slug == "coherent-breathing")
        #expect(lastRun?.at == newer.startedAt)
    }

    /// The rerun replays the same protocol, not an approximation. "Winding down"
    /// is five minutes of Extended Exhale; the plain exercise is a different
    /// session under the same name.
    @Test("A session a protocol prescribed is offered back as that protocol")
    func anOccasionStampedRecordRerunsTheOccasion() {
        let record = SessionRecord(
            techniqueSlug: "extended-exhale",
            startedAt: .now,
            duration: .seconds(300),
            cyclesCompleted: 10,
            breathCount: 10,
            completed: true,
            occasionSlug: "winding-down"
        )

        let stop = ShelfFixtures.shelf(history: [record]).lastRun?.stop

        #expect(stop?.id == "occasions/winding-down")
        #expect(stop?.occasionSlug == "winding-down")
    }

    /// The protocol has to still resolve. One the server has stopped sending
    /// leaves a record naming a technique that is very much still here, and the
    /// exercise standing for itself is the honest offer.
    @Test("A record naming a protocol nobody sends falls back to the exercise")
    func anUnresolvableOccasionFallsBackToTheExercise() {
        let record = SessionRecord(
            techniqueSlug: "extended-exhale",
            startedAt: .now,
            duration: .seconds(300),
            cyclesCompleted: 10,
            breathCount: 10,
            completed: true,
            occasionSlug: "a-moment-nobody-seeds"
        )

        #expect(ShelfFixtures.shelf(history: [record]).lastRun?.stop
            .id == "everything/extended-exhale")
    }

    /// A row that could not be started is worse than no row. The session is not
    /// lost — the History screen draws it against its slug — but Home has
    /// nothing to offer.
    @Test("A session whose exercise has left the catalogue offers no rerun")
    func aDeletedTechniqueOffersNoRerun() {
        let record = HomeFixtures.session("an-exercise-nobody-ships")

        #expect(ShelfFixtures.shelf(history: [record]).lastRun == nil)
    }

    @Test("An exercise somebody wrote is offered again as their own")
    func anAuthoredExerciseCanBeRerun() {
        let shelf = ShelfFixtures.shelf(
            history: [HomeFixtures.session("mine")],
            authored: [ShelfFixtures.authored]
        )

        #expect(shelf.lastRun?.stop.id == "yours/mine")
    }

    /// The rerun is an exercise standing for itself, never a rung: a rung's
    /// words are about where somebody is in a course, and replaying one would
    /// tell them they are at the start of something they have been doing for a
    /// month.
    @Test("A rerun of a rung's exercise is offered as the exercise")
    func aRerunIsNeverARung() {
        // 23:00 leads with a protocol while the repeat card resolves the
        // exercise that its progression rung prescribed.
        let shelf = ShelfFixtures.shelf(history: [HomeFixtures.session("box-breathing")], hour: 23)

        #expect(shelf.lastRun?.stop.band == .everything)
    }
}
