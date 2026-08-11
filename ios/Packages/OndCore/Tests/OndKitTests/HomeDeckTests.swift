import Foundation
@testable import OndKit
import Testing

/// The deck's order, which is the whole of what it adds over the dial's.
///
/// Every case here is a claim about *why* a card is where it is, because that is
/// what the layout is testing: whether home can justify its own order out loud.
@Suite("The deck's order")
struct HomeDeckTests {
    private static let routes = Routes(
        occasions: [
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
        ],
        progression: [
            ProgressionStep(techniqueSlug: "box-breathing", note: "Start here."),
            ProgressionStep(techniqueSlug: "physiological-sigh", note: "Seconds long."),
        ]
    )

    /// Twenty-three hundred, so the sleep occasion is what the hour routes to and
    /// the lead is a known stop rather than whatever the clock decided.
    private func dial(history: [SessionRecord]) -> HomeDial {
        HomeDial(
            techniques: SeededCatalogue.techniques,
            routes: Self.routes,
            history: history,
            hour: 23
        )
    }

    private func deck(history: [SessionRecord], starred: Set<String> = []) -> HomeDeck {
        let dial = dial(history: history)
        return HomeDeck(stops: dial.routed(), history: history, starred: starred)
    }

    private var day: TimeInterval {
        60 * 60 * 24
    }

    /// One session in hand, so the hour routes rather than Start here — the deck has
    /// to keep whatever the routing layer chose in front, not a rung.
    @Test("The routing layer's choice is the first card, and says so")
    func theLeadStaysInFront() {
        let deck = deck(history: [HomeFixtures.session(
            "box-breathing",
            at: .now.addingTimeInterval(-day)
        )])

        #expect(deck.cards.first?.reason == .suggested)
        #expect(deck.cards.first?.stop.title == "Winding down")
    }

    /// The pin the user asked for by name. Derived from history rather than from a
    /// favourites store, so it costs no schema — see `HomeDeck`.
    @Test("The last thing breathed is pinned near the front")
    func theLastSessionIsPinned() {
        let history = [
            HomeFixtures.session("box-breathing", at: .now.addingTimeInterval(-3 * day)),
            HomeFixtures.session("physiological-sigh", at: .now.addingTimeInterval(-day)),
        ]
        let deck = deck(history: history)
        let again = deck.cards.first { card in
            if case .again = card.reason {
                true
            } else {
                false
            }
        }

        #expect(again?.stop.technique.slug == "physiological-sigh")
        #expect(deck.cards.prefix(3).contains { $0.id == again?.id })
    }

    @Test("What somebody breathes often is pinned, most-breathed first")
    func theFamiliarArePinned() {
        let history = [
            HomeFixtures.session("box-breathing", at: .now.addingTimeInterval(-5 * day)),
            HomeFixtures.session("box-breathing", at: .now.addingTimeInterval(-4 * day)),
            HomeFixtures.session("box-breathing", at: .now.addingTimeInterval(-3 * day)),
            HomeFixtures.session("physiological-sigh", at: .now.addingTimeInterval(-2 * day)),
            HomeFixtures.session("physiological-sigh", at: .now.addingTimeInterval(-day)),
        ]
        let often = deck(history: history).cards.compactMap { card -> (String, Int)? in
            guard case let .often(count) = card.reason else { return nil }
            return (card.stop.technique.slug, count)
        }

        // The sigh was breathed last, so it is pinned as `again` and cannot also be
        // pinned as `often` — the box is what is left to count.
        #expect(often.first?.0 == "box-breathing")
        #expect(often.first?.1 == 3)
    }

    /// One curious tap is not a favourite. The threshold exists so a screen does
    /// not permanently rearrange itself around something tried once.
    @Test("A single session is not enough to pin anything")
    func onceIsNotOften() {
        let history = [HomeFixtures.session("box-breathing", at: .now.addingTimeInterval(-day))]
        let deck = deck(history: history)

        #expect(!deck.cards.contains { card in
            if case .often = card.reason {
                true
            } else {
                false
            }
        })
        #expect(deck.cards.contains { card in
            if case .again = card.reason {
                true
            } else {
                false
            }
        })
    }

    @Test("No history means no pins, and the dial's own order stands")
    func aFirstRunDeckIsTheDial() {
        let dial = HomeDial(
            techniques: SeededCatalogue.techniques,
            routes: Self.routes,
            history: [],
            hour: 23
        )
        let deck = HomeDeck(stops: dial.routed(), history: [])

        #expect(deck.cards.map(\.id) == dial.routed().map(\.id))
    }

    /// A pinned stop is moved, not copied. Two cards on one stop would be the same
    /// exercise twice in one flick, and the deck's ids would collide as a scroll
    /// position.
    @Test("A stop pinned twice over still appears once")
    func nothingIsDealtTwice() {
        let history = [
            HomeFixtures.session("extended-exhale", at: .now.addingTimeInterval(-2 * day)),
            HomeFixtures.session("extended-exhale", at: .now.addingTimeInterval(-day)),
        ]
        let deck = deck(history: history)

        #expect(Set(deck.cards.map(\.id)).count == deck.cards.count)
    }

    @Test("Every card that has no better reason says what kind of thing it is")
    func theRestSayWhatTheyAre() {
        let deck = deck(history: [])

        #expect(deck.cards.contains { $0.reason == .moment })
        #expect(deck.cards.contains { $0.reason == .step })
    }

    /// The one thing on this screen somebody curates, so it outranks everything the
    /// deck worked out for itself — but not the lead, which is still the app's answer
    /// to *now*, and a star made on another day cannot be.
    @Test("A starred card comes second, behind the hour's own suggestion")
    func aStarBeatsEveryDerivedPin() {
        let history = [
            HomeFixtures.session("box-breathing", at: .now.addingTimeInterval(-2 * day)),
            HomeFixtures.session("box-breathing", at: .now.addingTimeInterval(-day)),
        ]
        let starred = dial(history: history).routed()
            .filter { $0.technique.slug == "physiological-sigh" }
            .map(\.id)
        let cards = deck(history: history, starred: Set(starred)).cards

        #expect(cards.first?.reason == .suggested)
        #expect(cards.dropFirst().first?.reason == .starred)
        #expect(cards.dropFirst().first?.stop.technique.slug == "physiological-sigh")
    }

    /// A set has no order, so where two stars sit has to come from somewhere. It comes
    /// from the dial, which means starring can never become a second sort.
    @Test("Two starred cards keep the order home would have shown them in")
    func starsKeepDialOrder() {
        let routed = dial(history: []).routed()
        let starred = Set(routed.suffix(2).map(\.id))
        let cards = HomeDeck(stops: routed, history: [], starred: starred).cards
        let stars = cards.filter { $0.reason == .starred }.map(\.id)

        #expect(stars == routed.filter { starred.contains($0.id) }.map(\.id))
    }

    /// A star on the lead is not a second card. The reason line stays the hour's —
    /// the glyph on the card is what says it is starred.
    @Test("Starring what is already suggested does not deal it twice")
    func starringTheLeadChangesNothing() {
        let routed = dial(history: []).routed()
        let cards = HomeDeck(
            stops: routed,
            history: [],
            starred: [routed[0].id]
        ).cards

        #expect(cards.map(\.id) == routed.map(\.id))
        #expect(cards.first?.reason == .suggested)
    }

    /// A star's only effect is to move a card to the front, and the suggestion is
    /// already there — so the control would visibly do nothing on the one card that
    /// cannot be promoted.
    @Test("Every card offers a star except the one already in front")
    func onlyTheSuggestionRefusesAStar() {
        let cards = deck(history: []).cards

        #expect(cards.first?.reason.acceptsStar == false)
        #expect(!cards.dropFirst().contains { !$0.reason.acceptsStar })
    }

    /// A filled star and the word "Starred" are one fact twice. The words survive for
    /// VoiceOver, which reads a label rather than a corner.
    @Test("A starred card does not print the reason its glyph already gives")
    func aStarNeedsNoCaption() {
        #expect(!HomeDeck.Reason.starred.isSpelled)
        #expect(HomeDeck.Reason.starred.phrase == "Starred")

        for reason in [HomeDeck.Reason.suggested, .moment, .step, .yours, .catalogue] {
            #expect(reason.isSpelled)
        }
    }

    /// The routes are the server's and a star is this device's, so a starred id can
    /// outlive the card it named.
    @Test("A star naming a stop home no longer offers is inert")
    func aStaleStarIsIgnored() {
        let routed = dial(history: []).routed()
        let cards = HomeDeck(stops: routed, history: [], starred: ["occasions/gone"]).cards

        #expect(cards.map(\.id) == routed.map(\.id))
        #expect(!cards.contains { $0.reason == .starred })
    }

    /// An exercise somebody wrote themselves, on a slug no seeded technique uses.
    ///
    /// `origin` is stated rather than defaulted, because `DialStop.id(of:)` reads it
    /// to answer which band this exercise's card lives in.
    private static let authored = Technique(
        id: "mine",
        slug: "my-own-square",
        name: "My own square",
        summary: "Mine.",
        goal: .calm,
        stages: [Stage(
            phases: [
                Phase(kind: .inhale, duration: .seconds(4)),
                Phase(kind: .exhale, duration: .seconds(4)),
            ],
            cycles: 6
        )],
        recommendedRounds: 1,
        origin: .personal
    )

    private func deck(authored: [Technique], starred: Set<String> = []) -> HomeDeck {
        let dial = HomeDial(
            techniques: SeededCatalogue.techniques,
            routes: Self.routes,
            history: [],
            hour: 23,
            authored: authored
        )
        return HomeDeck(stops: dial.routed(), history: [], starred: starred)
    }

    /// Home is the one screen that used to pretend an authored exercise did not exist.
    /// `HomeDial` gained a band for them; this is the half that matters to somebody
    /// looking at the board, and it was untested until it was asked about.
    @Test("An exercise this person wrote is dealt as a card, and says it is theirs")
    func anAuthoredExerciseIsACard() {
        let mine = deck(authored: [Self.authored]).cards
            .first { $0.stop.technique.slug == Self.authored.slug }

        #expect(mine?.reason == .yours)
        #expect(mine?.reason.brief == "Yours")
        #expect(mine?.stop.band == .yours)
    }

    /// Where it lands, stated rather than assumed — and it is the back of the board,
    /// behind every occasion and every rung. That follows from `DialBand`'s own order
    /// and it sits awkwardly beside `HomeDial.routed(starring:)`'s stated reason for keeping the
    /// band at all: that an exercise somebody wrote is the one they are likeliest to
    /// want again. Pinned here, so moving it forward is a decision somebody makes on
    /// purpose rather than a test quietly changing its mind.
    @Test("An authored exercise is dealt last, behind everything home routes to")
    func anAuthoredExerciseIsDealtLast() {
        let cards = deck(authored: [Self.authored]).cards

        #expect(cards.last?.stop.technique.slug == Self.authored.slug)
        #expect(cards.dropLast().allSatisfy { card in card.stop.band != .yours })
    }

    /// The way out of the back of the board, and the reason starring earns its keep
    /// beyond convenience: it is the only thing that can put an authored exercise in
    /// front of the app's own suggestions. The composer does exactly this on every new
    /// exercise — see `TechniqueComposerView.save()`.
    @Test("Starring an authored exercise brings it to the front")
    func anAuthoredExerciseCanBeStarred() {
        let mine = DialStop.id(of: Self.authored)
        let cards = deck(authored: [Self.authored], starred: [mine]).cards

        #expect(cards.dropFirst().first?.stop.technique.slug == Self.authored.slug)
        #expect(cards.dropFirst().first?.reason == .starred)
    }

    /// The join the composer and the detail screen's toolbar both rest on. Each stars
    /// an exercise before home has built a stop for it, so each has to name the id the
    /// stop *will* carry — and if these two strings ever part company the symptom is
    /// silent: a star that pins nothing.
    @Test("The id an exercise is starred by is the id its card turns up with")
    func theAuthoredIdMatchesTheCard() {
        let card = deck(authored: [Self.authored]).cards
            .first { $0.stop.technique.slug == Self.authored.slug }

        #expect(card?.id == DialStop.id(of: Self.authored))
    }

    @Test("An empty dial deals no cards")
    func anEmptyDialIsAnEmptyDeck() {
        #expect(HomeDeck(stops: [], history: []).cards.isEmpty)
    }
}
