import Foundation
@testable import OndKit
import Testing

/// Starring an exercise from its own screen, from the id it is starred by through
/// to the card home deals for it.
///
/// Its own suite rather than more of `HomeDialTests` and `HomeDeckTests`, for the
/// reason `HomeDialAuthoredTests` is its own: the question is about one path
/// crossing both types — a star made two tabs away has to survive the routing
/// filter and then earn a place in the deck — rather than about either type's
/// internal rules. The routing filter and the deck order are checked together
/// here because separately they can each be right while the path is broken.
@Suite("Starring an exercise from its own screen")
struct HomeStarredExerciseTests {
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

    /// A catalogue entry nothing routes to: no occasion prescribes it and it is on
    /// no rung, so a star is the only way it reaches home.
    private static let unrouted = SeededCatalogue.technique("coherent-breathing")

    /// Twenty-three hundred, so the sleep occasion is what the hour routes to and
    /// the lead is a known stop rather than whatever the clock decided.
    private func dial(
        history: [SessionRecord] = [],
        hour: Int = 23,
        routes: Routes = HomeStarredExerciseTests.routes
    ) -> HomeDial {
        HomeDial(
            techniques: SeededCatalogue.techniques,
            routes: routes,
            history: history.isEmpty ? [HomeFixtures.session("box-breathing")] : history,
            hour: hour
        )
    }

    // MARK: what the toolbar star reads

    /// Box Breathing is a rung of Start here, so starring it on the board writes
    /// `startHere/box-breathing` — and the toolbar star two tabs away has to see it.
    /// Reading only `id(of:)` drew an empty star over an exercise already pinned,
    /// and dealt a second identical row into a four-slot shortlist when it was
    /// pressed.
    @Test("An exercise starred as any of its cards reads as starred")
    func aStarOnAnyBandIsTheExerciseStarred() {
        let box = SeededCatalogue.technique("box-breathing")
        let cards = DialStop.ids(standingFor: box)

        #expect(cards.contains("startHere/box-breathing"))
        #expect(cards.contains(DialStop.id(of: box)))
        #expect(!cards.isDisjoint(with: ["startHere/box-breathing"]))
    }

    /// The occasions are keyed by the moment, not the exercise. "Winding down"
    /// prescribes Extended Exhale, and a toolbar star that cleared the moment by
    /// pressing the exercise would take away something nobody pointed at.
    @Test("Starring an occasion is not starring the exercise it prescribes")
    func anOccasionIsNotTheExercise() {
        let prescribed = SeededCatalogue.technique("extended-exhale")

        #expect(DialStop.ids(standingFor: prescribed).isDisjoint(with: ["occasions/winding-down"]))
    }

    /// The gap this closed. Nothing routes to most of the catalogue — no seeded
    /// occasion borrows `energy` or `focus` — so an exercise found in the Exercises
    /// tab could be breathed daily and never pinned.
    @Test("A starred catalogue exercise is routed, and nothing else changes")
    func aStarredCatalogueStopIsRouted() {
        let dial = dial()
        let starred = DialStop.id(of: Self.unrouted)

        #expect(!dial.routed().contains { $0.id == starred })
        #expect(dial.routed(starring: [starred]).contains { $0.id == starred })
        #expect(dial.routed(starring: [starred]).count == dial.routed().count + 1)
    }

    /// Dial order, not star order — `everything` is the last band, so a starred
    /// catalogue entry sits behind every moment and every rung. Where it goes from
    /// there is `HomeDeck`'s decision, and it is the one that moves it forward.
    @Test("A starred catalogue exercise is routed behind every route")
    func aStarredCatalogueStopKeepsDialOrder() {
        let routed = dial().routed(starring: [DialStop.id(of: Self.unrouted)])

        #expect(routed.last?.id == DialStop.id(of: Self.unrouted))
        #expect(routed.dropLast().allSatisfy { $0.band != .everything })
    }

    /// The regression the obvious implementation introduces. The lead can be a
    /// catalogue entry — that is the ordinary case for most of a working day — and
    /// somebody starring what home just offered them is the likeliest star there is.
    /// Prepending a lead the filter has already kept puts one stop on the dial twice,
    /// and two stops sharing an id is a card home can neither draw nor step onto.
    @Test("A starred lead is still routed exactly once, and still first")
    func theLeadIsNotRoutedTwiceWhenItIsStarred() {
        let breathed = Self.progression.map { HomeFixtures.session($0.techniqueSlug) }
        let dial = dial(history: breathed, hour: 8)

        guard let lead = dial.lead else {
            Issue.record("the dial has no lead")
            return
        }

        let routed = dial.routed(starring: [lead.id])

        #expect(lead.band == .everything)
        #expect(routed.first?.id == lead.id)
        #expect(routed.filter { $0.id == lead.id }.count == 1)
        #expect(routed.count == dial.routed().count)
    }

    /// A star must never take an exercise away. Emptiness is decided on the routed
    /// bands rather than on the starred set for exactly this: a device that has never
    /// reached the server falls back to the whole catalogue, and folding the stars in
    /// first would turn that fallback into a home screen holding the single card the
    /// star named.
    @Test("A star does not shrink the no-routes fallback to itself")
    func aStarDoesNotShrinkTheNoRoutesFallback() {
        let routed = dial(routes: .none).routed(starring: [DialStop.id(of: Self.unrouted)])

        #expect(routed.count == SeededCatalogue.techniques.count)
    }

    // MARK: the card

    @Test("A starred catalogue exercise is dealt as its own card, near the front")
    func aStarredCatalogueExerciseIsItsOwnCard() {
        let starred = DialStop.id(of: Self.unrouted)
        let cards = HomeDeck(
            stops: dial().routed(starring: [starred]),
            history: [],
            starred: [starred]
        ).cards

        #expect(cards.dropFirst().first?.id == starred)
        #expect(cards.dropFirst().first?.reason == .starred)
        #expect(cards.dropFirst().first?.reason.isShortlisted == true)
        #expect(cards.dropFirst().first?.stop.band == .everything)
    }

    /// Asymmetric with every other band, and correct: a star is the only thing
    /// holding a catalogue entry on the board, so taking the star off takes the card
    /// off. Unstarring a routed card only puts it back in its own order.
    @Test("Unstarring a catalogue exercise takes its card off the board")
    func unstarringACatalogueCardTakesItOffTheBoard() {
        let cards = HomeDeck(stops: dial().routed(), history: [], starred: []).cards

        #expect(!cards.contains { $0.id == DialStop.id(of: Self.unrouted) })
    }

    /// The decision this was built to, pinned so that reversing it has to be an
    /// argument rather than an accident. A star from an exercise's own screen is
    /// about the exercise, so it deals a card of its own even where a rung or an
    /// occasion already prescribes the same technique under different words.
    @Test("A starred exercise the routes already offer is dealt twice, as two cards")
    func aStarredExerciseMayDoubleOneTheRoutesOffer() {
        let starred = DialStop.id(of: SeededCatalogue.technique("box-breathing"))
        let cards = HomeDeck(
            stops: dial().routed(starring: [starred]),
            history: [],
            starred: [starred]
        ).cards
        let boxes = cards.filter { $0.stop.technique.slug == "box-breathing" }

        #expect(boxes.count == 2)
        #expect(Set(boxes.map(\.id)).count == 2)
        #expect(boxes.contains { $0.reason == .starred })
        #expect(boxes.contains { $0.stop.band == .startHere })
    }
}
