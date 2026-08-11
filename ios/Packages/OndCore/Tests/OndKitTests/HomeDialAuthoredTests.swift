import Foundation
@testable import OndKit
import Testing

/// Home was the one screen in the app that pretended an authored exercise did not
/// exist: `HomeView` was never handed `own`, and `HomeDial` had no band to put
/// one in — so somebody who had composed an exercise could reach it only from the
/// Exercises tab. Its own suite rather than more of `HomeDialTests`, because the
/// question is about a second source of exercises rather than about the dial's
/// routing rules.
@Suite("The dial's authored band")
struct HomeDialAuthoredTests {
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
        ProgressionStep(techniqueSlug: "physiological-sigh", note: "The one that takes seconds."),
    ]

    private static let routes = Routes(occasions: occasions, progression: progression)

    /// One exercise somebody composed, on a slug no seeded technique uses — so the
    /// `yours` band cannot be satisfied by a catalogue entry wearing it.
    ///
    /// `origin` is stated rather than defaulted, which the rest of the fixtures in
    /// these suites can afford and this one cannot: it is what `DialStop.id(of:)`
    /// reads to answer which band this exercise's card lives in.
    private static let authored = Technique(
        id: "mine",
        slug: "mine",
        name: "My own square",
        summary: "",
        goal: .calm,
        stages: [Stage(phases: [Phase(kind: .inhale, duration: .seconds(4))], cycles: 1)],
        recommendedRounds: 1,
        origin: .personal
    )

    private func dial(hour: Int, authored: [Technique] = [Self.authored]) -> HomeDial {
        HomeDial(
            techniques: SeededCatalogue.techniques,
            routes: Self.routes,
            history: [HomeFixtures.session("box-breathing")],
            hour: hour,
            authored: authored
        )
    }

    @Test("An exercise this person wrote is a stop, in its own band")
    func authoredExercisesBecomeStops() {
        let stops = dial(hour: 23).stops.filter { $0.band == .yours }

        #expect(stops.count == 1)
        #expect(stops.first?.title == Self.authored.name)
    }

    /// The band exists so home stops being the screen that hides them, which only
    /// holds if the phone's filtered dial keeps it — `routed` drops `everything`,
    /// and `yours` had to land on the other side of that line.
    @Test("An authored exercise survives the routed filter")
    func authoredExercisesAreRouted() {
        let dial = dial(hour: 23)

        #expect(dial.routed().contains { $0.band == .yours })
        #expect(dial.routed().contains { $0.title == Self.authored.name })
    }

    /// Nothing routes to an authored exercise: the occasions name catalogue slugs,
    /// the progression is curated, and the hour's suggestion reads goals the
    /// catalogue publishes. A lead from `yours` would be the app recommending back
    /// what it was handed.
    @Test("An authored exercise is never what home leads with, at any hour")
    func authoredExercisesNeverLead() {
        for hour in 0 ..< 24 {
            #expect(dial(hour: hour).lead?.band != .yours)
        }
    }

    /// A catalogue slug and an authored slug can collide — two services, and only
    /// one of them is seeded — and two stops sharing an id is a stop the dial can
    /// neither spin to nor step onto.
    @Test("An authored exercise sharing a catalogue slug is still its own stop")
    func acollidingSlugStaysTwoStops() {
        let collision = Technique(
            id: "box-breathing",
            slug: "box-breathing",
            name: "My box breathing",
            summary: "",
            goal: .calm,
            stages: [Stage(phases: [Phase(kind: .inhale, duration: .seconds(4))], cycles: 1)],
            recommendedRounds: 1
        )
        let stops = dial(hour: 23, authored: [collision]).stops

        #expect(stops.filter { $0.band == .yours }.count == 1)
        #expect(Set(stops.map(\.id)).count == stops.count)
    }

    @Test("Somebody who has written nothing has no authored band at all")
    func noAuthoredExercisesMeansNoBand() {
        let stops = dial(hour: 23, authored: []).stops

        #expect(!stops.contains { $0.band == .yours })
    }

    /// The complement of `HomeDialTests.everyBandIsOnTheDial`, which asserts the
    /// three a routed device always has: with an authored exercise in hand, every
    /// band the enum declares is on the dial.
    @Test("With an authored exercise, every declared band is on the dial")
    func everyBandIsReachable() {
        #expect(Set(dial(hour: 23).stops.map(\.band)) == Set(DialBand.allCases))
    }

    /// `DialStop.id(of:)` answers before a card exists, which is what lets the
    /// composer and an exercise's own screen star one — and it derives the band from
    /// `origin`, where the dial derives it from which list the technique arrived in.
    /// Nothing makes those two agree, so this does: the day somebody hands authored
    /// exercises in through `techniques:`, a star stops pinning anything and this is
    /// what says so.
    @Test("A standalone stop carries the id its own technique answers with")
    func everyStandaloneStopCarriesTheIdItsTechniqueAnswersWith() {
        for stop in dial(hour: 23).stops where stop.origin == .technique {
            #expect(stop.id == DialStop.id(of: stop.technique))
        }
    }

    @Test("The id of an exercise names the band its card lives in")
    func theIdOfATechniqueNamesItsBand() {
        #expect(DialStop.id(of: Self.authored) == "yours/mine")
        #expect(
            DialStop.id(of: SeededCatalogue.technique("box-breathing"))
                == "everything/box-breathing"
        )
    }
}
