import Foundation
@testable import OndKit
import Testing

/// Everything Home offers to breathe: what the hour suggests, what was breathed
/// last, and what this person starred.
///
/// Over the catalogue the apps actually ship and routes shaped like the ones
/// `crates/migrate` seeds, on the dial suite's reasoning — a slug that stops
/// resolving should fail here rather than show up as a row that quietly
/// vanished.
@Suite("Home's shelf")
struct HomeShelfTests {
    private static func prescription(
        _ slug: String,
        goal: TechniqueGoal,
        minutes: Int = 5
    ) -> Prescription {
        Prescription(
            techniqueSlug: slug,
            goal: goal,
            surface: .fullScreen,
            duration: .seconds(minutes * 60)
        )
    }

    private static let occasions = [
        Occasion(
            slug: "winding-down",
            name: "Winding down",
            summary: "Long, slow out-breaths.",
            prescription: prescription("extended-exhale", goal: .sleep)
        ),
    ]

    private static let progression = [
        ProgressionStep(techniqueSlug: "box-breathing", note: "Start here."),
        ProgressionStep(techniqueSlug: "physiological-sigh", note: "Seconds long."),
        ProgressionStep(techniqueSlug: "extended-exhale", note: "The lever underneath."),
    ]

    private static let routes = Routes(occasions: occasions, progression: progression)

    /// A catalogue entry nothing routes to: no protocol prescribes it and it is
    /// on no rung, so a star is the only way it reaches Home.
    private static let unrouted = SeededCatalogue.technique("coherent-breathing")

    /// One exercise somebody composed, on a slug no seeded technique uses.
    /// `origin` is stated rather than defaulted because it is the whole of what
    /// `DialStop.id(of:)` reads to answer which band this exercise's row lives
    /// in.
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

    /// Fourteen hundred by default, which `HomeSuggestion` reads as `focus` — a
    /// goal no protocol here borrows, so the suggestion is a known fallback
    /// rather than whatever the clock decided.
    private func shelf(
        starred: Set<DialStop.ID> = [],
        history: [SessionRecord] = [],
        hour: Int = 14,
        routes: Routes = HomeShelfTests.routes,
        dialled: [String: TechniqueOverrides] = [:],
        authored: [Technique] = []
    ) -> HomeShelf {
        HomeShelf(
            techniques: SeededCatalogue.techniques,
            routes: routes,
            history: history,
            starred: starred,
            hour: hour,
            dialled: dialled,
            authored: authored
        )
    }

    // MARK: what Home leads with

    @Test("Somebody who has breathed nothing leads with the first rung of Start here")
    func firstRunLeadsWithTheProgression() {
        let suggested = shelf().suggested

        #expect(suggested?.band == .startHere)
        #expect(suggested?.title == SeededCatalogue.technique("box-breathing").name)
    }

    @Test("Somebody with history leads with the protocol the hour fits")
    func theHourPicksTheOccasion() {
        // 23:00 is `sleep` by `HomeSuggestion`, and one protocol borrows it.
        let suggested = shelf(history: [HomeFixtures.session("box-breathing")], hour: 23).suggested

        #expect(suggested?.title == "Winding down")
        #expect(suggested?.goal == .sleep)
        // The prescription travels with it, which is the whole reason a protocol
        // beats the plain exercise here: the same technique, at the length and in
        // the register the moment asked for.
        #expect(suggested?.occasionSlug == "winding-down")
        #expect(suggested?.dose != nil)
    }

    @Test("The rung led with advances as each one is breathed")
    func theProgressionIsReadFromTheirOwnHistory() {
        // 08:00 is `energy`, which no protocol here borrows, so the lead is the
        // progression's.
        let two = [
            HomeFixtures.session("box-breathing"),
            HomeFixtures.session("physiological-sigh"),
        ]

        #expect(shelf(history: two, hour: 8).suggested?.technique.slug == "extended-exhale")
        #expect(shelf(history: [], hour: 8).suggested?.technique.slug == "box-breathing")
    }

    /// The regression the review found: `JourneyModel.history` is newest first,
    /// and the rule read "last used" off the array's order rather than off the
    /// dates — so a returning person was offered the first thing they ever
    /// breathed.
    @Test("With every rung breathed, the fallback is the last exercise used for the hour's goal")
    func theFallbackIsTheLastUsedRatherThanTheFirst() {
        let breathed = Self.progression.map { HomeFixtures.session($0.techniqueSlug) }
        // Both are `focus`, which 14:00 routes to and no protocol here borrows.
        let focused = [
            HomeFixtures.session("long-box-breathing", at: .now.addingTimeInterval(-7200)),
            HomeFixtures.session("alternate-nostril", at: .now.addingTimeInterval(-60)),
        ]

        let suggested = shelf(history: breathed + focused).suggested

        #expect(suggested?.technique.slug == "alternate-nostril")
        #expect(suggested?.band == .everything)
    }

    @Test("With no routes at all, the lead is still the hour's own suggestion")
    func aDeviceWithNoRoutesStillLeadsWithSomething() {
        let suggested = shelf(
            history: [HomeFixtures.session("box-breathing")],
            hour: 23,
            routes: .none
        ).suggested

        #expect(suggested?.band == .everything)
        #expect(suggested?.goal == .sleep)
    }

    @Test("An empty catalogue leads with nothing rather than something invented")
    func anEmptyCatalogueLeadsWithNothing() {
        let shelf = HomeShelf(
            techniques: [], routes: .none, history: [], starred: [], hour: 14
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

        let breathed = Self.progression.map { HomeFixtures.session($0.techniqueSlug) }
        let suggested = shelf(
            history: breathed + [HomeFixtures.session("alternate-nostril")],
            dialled: [nostril.slug: longer]
        ).suggested

        #expect(suggested?.dose == longer)
        #expect(suggested?.duration == nostril.dialled(with: longer).plannedDuration)
    }

    // MARK: nothing appears twice

    /// `HomeDeck` guarded this with a `place()` that admitted an id once. The
    /// guard moved here with the sections it protects: a regular practising one
    /// exercise every evening would otherwise meet it as the suggestion, the
    /// rerun and a star, three rows in a column.
    @Test("A stop offered by two rules appears once, under the earlier one")
    func nothingIsShelvedTwice() {
        let history = [HomeFixtures.session("extended-exhale")]
        let shelf = shelf(
            starred: ["occasions/winding-down", "everything/extended-exhale"],
            history: history,
            hour: 23
        )

        let shown = [shelf.suggested?.id].compactMap(\.self)
            + [shelf.lastRun?.stop.id].compactMap(\.self)
            + shelf.starred.map(\.id)

        #expect(Set(shown).count == shown.count)
        // Both stars were already on screen — one as the hour's protocol, one as
        // the rerun — so the Starred section is empty rather than a third and
        // fourth copy of them. Neither loses its star: both rows carry one.
        #expect(shelf.suggested?.id == "occasions/winding-down")
        #expect(shelf.lastRun?.stop.id == "everything/extended-exhale")
        #expect(shelf.starred.isEmpty)
    }

    @Test("The rerun gives way to the suggestion rather than repeating it")
    func theRerunNeverRepeatsTheSuggestion() {
        // 08:00 routes to no protocol, and every rung is breathed, so the lead
        // falls through to the last `energy` exercise used — which is also the
        // most recent session.
        let breathed = Self.progression.enumerated().map { offset, step in
            HomeFixtures.session(
                step.techniqueSlug,
                at: .now.addingTimeInterval(TimeInterval(-3600 * (offset + 2)))
            )
        }
        let shelf = shelf(
            history: breathed + [HomeFixtures.session("bellows-breath", at: .now)],
            hour: 8
        )

        #expect(shelf.suggested?.technique.slug == "bellows-breath")
        #expect(shelf.lastRun == nil)
    }

    // MARK: what a star resolves to

    /// The path a star made two tabs away has to survive. Nothing routes to most
    /// of the catalogue — no seeded protocol borrows `energy` or `focus` — so an
    /// exercise found on the Exercises tab could be breathed daily and never
    /// reach Home without this.
    @Test("A star made on an exercise's own screen becomes a shelf row")
    func aStarredCatalogueExerciseIsShelved() {
        let starred = DialStop.id(of: Self.unrouted)

        #expect(shelf(starred: [starred]).starred.map(\.id) == [starred])
    }

    @Test("A star resolves in whichever band it names", arguments: [
        "occasions/winding-down",
        "startHere/physiological-sigh",
        "everything/coherent-breathing",
    ])
    func everyBandAnswersAStar(_ id: DialStop.ID) {
        #expect(shelf(starred: [id]).starred.map(\.id) == [id])
    }

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
            "yours/mine",
            "occasions/winding-down",
            "startHere/physiological-sigh",
        ]

        #expect(shelf(starred: ids, authored: [Self.authored]).starred.map(\.id) == [
            "occasions/winding-down",
            "startHere/physiological-sigh",
            "yours/mine",
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

        // Newest first, the order `JourneyModel` hands it over in, so a rule
        // reading the array's order rather than the dates fails here.
        let lastRun = shelf(history: [newer, older]).lastRun

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

        let stop = shelf(history: [record]).lastRun?.stop

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

    @Test("An exercise somebody wrote is offered again as their own")
    func anAuthoredExerciseCanBeRerun() {
        let shelf = shelf(
            history: [HomeFixtures.session("mine")],
            authored: [Self.authored]
        )

        #expect(shelf.lastRun?.stop.id == "yours/mine")
    }

    /// The rerun is an exercise standing for itself, never a rung: a rung's
    /// words are about where somebody is in a course, and replaying one would
    /// tell them they are at the start of something they have been doing for a
    /// month.
    @Test("A rerun of a rung's exercise is offered as the exercise")
    func aRerunIsNeverARung() {
        // 23:00 leads with the protocol, so the rerun is not swallowed by the
        // dedupe before it can be looked at.
        let shelf = shelf(history: [HomeFixtures.session("box-breathing")], hour: 23)

        #expect(shelf.lastRun?.stop.band == .everything)
    }
}
