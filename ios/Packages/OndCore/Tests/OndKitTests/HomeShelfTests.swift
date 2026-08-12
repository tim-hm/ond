import Foundation
@testable import OndKit
import Testing

/// What Home puts in front of somebody that it did not work out for itself: the
/// stars, and the last thing breathed.
///
/// Over the catalogue the apps actually ship and routes shaped like the ones
/// `crates/migrate` seeds, on `HomeDialTests`' reasoning — a slug that stops
/// resolving should fail here rather than show up as a row that quietly
/// vanished.
@Suite("Home's shelf")
struct HomeShelfTests {
    private static let occasions = [
        Occasion(
            slug: "winding-down",
            name: "Winding down",
            summary: "Long, slow out-breaths.",
            prescription: Prescription(
                techniqueSlug: "extended-exhale",
                goal: .sleep,
                surface: .fullScreen,
                duration: .seconds(300)
            )
        ),
    ]

    private static let progression = [
        ProgressionStep(techniqueSlug: "box-breathing", note: "Start here."),
        ProgressionStep(techniqueSlug: "physiological-sigh", note: "Seconds long."),
    ]

    private static let routes = Routes(occasions: occasions, progression: progression)

    /// A catalogue entry nothing routes to: no occasion prescribes it and it is
    /// on no rung, so a star is the only way it reaches Home.
    private static let unrouted = SeededCatalogue.technique("coherent-breathing")

    private func shelf(
        starred: Set<DialStop.ID> = [],
        history: [SessionRecord] = [],
        routes: Routes = HomeShelfTests.routes,
        authored: [Technique] = []
    ) -> HomeShelf {
        HomeShelf(
            techniques: SeededCatalogue.techniques,
            routes: routes,
            history: history,
            starred: starred,
            authored: authored
        )
    }

    // MARK: what a star resolves to

    /// The path a star made two tabs away has to survive. Nothing routes to most
    /// of the catalogue — no seeded occasion borrows `energy` or `focus` — so an
    /// exercise found on the Exercises tab could be breathed daily and never
    /// reach Home without this.
    @Test("A star made on an exercise's own screen becomes a shelf row")
    func aStarredCatalogueExerciseIsShelved() {
        let starred = DialStop.id(of: Self.unrouted)

        #expect(shelf(starred: [starred]).starred.map(\.id) == [starred])
    }

    /// Box Breathing is a rung of Start here, so starring it writes
    /// `startHere/box-breathing`. Every band answers a star, not only the
    /// catalogue's.
    @Test("A star resolves in whichever band it names", arguments: [
        "occasions/winding-down",
        "startHere/box-breathing",
        "everything/coherent-breathing",
    ])
    func everyBandAnswersAStar(_ id: DialStop.ID) {
        #expect(shelf(starred: [id]).starred.map(\.id) == [id])
    }

    /// Somebody's own exercises are a band like the others, and the one whose
    /// stops nobody but their author can see. `origin` is stated rather than
    /// defaulted because it is the whole of what `DialStop.id(of:)` reads to
    /// answer which band this exercise's row lives in.
    private static let authored = Technique(
        id: "mine",
        slug: "mine",
        name: "My own square",
        summary: "Four counts, four ways.",
        goal: .calm,
        stages: [Stage(phases: [Phase(kind: .inhale, duration: .seconds(4))], cycles: 1)],
        recommendedRounds: 1,
        origin: .personal
    )

    @Test("An authored exercise is starred in its own band")
    func theAuthoredBandAnswersAStar() {
        let starred = DialStop.id(of: Self.authored)

        #expect(starred == "yours/mine")
        #expect(
            shelf(starred: [starred], authored: [Self.authored]).starred.map(\.id) == [starred]
        )
    }

    /// Dial order rather than star order, which is why `StarredStopStore` holds
    /// a set: two stars stay in the order Home would have shown them anyway.
    @Test("Stars keep dial order, whatever order they were set in")
    func starsKeepDialOrder() {
        let ids: Set<DialStop.ID> = [
            "everything/coherent-breathing",
            "occasions/winding-down",
            "startHere/box-breathing",
        ]

        #expect(shelf(starred: ids).starred.map(\.id) == [
            "occasions/winding-down",
            "startHere/box-breathing",
            "everything/coherent-breathing",
        ])
    }

    /// No star migration was run, so the keyspace still holds ids for stops the
    /// routes no longer send. They pin nothing, silently — which is the right
    /// answer for a key naming something that no longer exists.
    @Test("An id nothing resolves pins nothing")
    func inertIdsPinNothing() {
        let shelf = shelf(starred: [
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
        #expect(shelf().starred.isEmpty)
        #expect(shelf(routes: .none).starred.isEmpty)
    }

    // MARK: the last thing breathed

    @Test("Nothing breathed is nothing to pick up")
    func noHistoryIsNoRerun() {
        #expect(shelf().lastRun == nil)
    }

    @Test("The most recent session is the one offered again")
    func theRerunIsTheMostRecent() {
        let older = HomeFixtures.session("box-breathing", at: .now.addingTimeInterval(-7200))
        let newer = HomeFixtures.session("coherent-breathing", at: .now.addingTimeInterval(-60))

        let lastRun = shelf(history: [newer, older]).lastRun

        #expect(lastRun?.stop.technique.slug == "coherent-breathing")
        #expect(lastRun?.at == newer.startedAt)
    }

    /// The rerun replays the same protocol, not an approximation of it. "Winding
    /// down" is five minutes of Extended Exhale; the plain exercise is a
    /// different session under the same name.
    @Test("A session an occasion prescribed is offered back as that occasion")
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

        let stop = shelf(history: [record]).lastRun?.stop

        #expect(stop?.id == "occasions/winding-down")
        #expect(stop?.occasionSlug == "winding-down")
    }

    /// The occasion has to still resolve. One the server has stopped sending
    /// leaves a record naming a technique that is very much still here, and the
    /// exercise standing for itself is the honest offer.
    @Test("A record naming an occasion nobody sends falls back to the exercise")
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

        #expect(shelf(history: [record]).lastRun?.stop.id == "everything/extended-exhale")
    }

    /// A row that could not be started is worse than no row. The session is not
    /// lost — the History screen draws it against its slug — but Home has
    /// nothing to offer.
    @Test("A session whose exercise has left the catalogue offers no rerun")
    func aDeletedTechniqueOffersNoRerun() {
        let record = HomeFixtures.session("an-exercise-nobody-ships")

        #expect(shelf(history: [record]).lastRun == nil)
    }

    /// The rerun is an exercise standing for itself, never a rung: a rung's
    /// words are about where somebody is in a course, and replaying one would
    /// tell them they are at the start of something they have been doing for a
    /// month.
    @Test("A rerun of a rung's exercise is offered as the exercise")
    func aRerunIsNeverARung() {
        #expect(shelf(history: [HomeFixtures.session("box-breathing")]).lastRun?.stop.band
            == .everything)
    }
}
