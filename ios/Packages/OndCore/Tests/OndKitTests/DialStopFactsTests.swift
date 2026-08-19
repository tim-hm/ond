import Foundation
@testable import OndKit
import Testing

/// What a home card says about a stop before anybody taps it.
///
/// Here rather than in either layout's file because both surfaces read the same
/// sentence and neither can be tested: the strip prints it and the board can only
/// reach it through an accessibility label, and the app targets have no test
/// bundle. What the regression was — a board that showed a lock and a wrist as
/// glyphs and said neither out loud — is exactly a wording bug, so the wording is
/// what gets pinned.
@Suite("A stop's facts")
struct DialStopFactsTests {
    /// A minute of breathing, so the length in the sentence is one this test
    /// chose rather than one the catalogue happens to hold.
    private static func technique(
        requires: SubscriptionTier = .free,
        goal: TechniqueGoal = .calm
    ) -> Technique {
        Technique(
            id: "t",
            slug: "steady",
            name: "Steady",
            summary: "",
            goal: goal,
            stages: [
                Stage(
                    phases: [
                        Phase(kind: .inhale, duration: .seconds(5)),
                        Phase(kind: .exhale, duration: .seconds(5)),
                    ],
                    cycles: 6
                ),
            ],
            recommendedRounds: 1,
            requires: requires
        )
    }

    /// A stop standing for itself, or — where a surface or a goal of the
    /// occasion's own is asked for — one reached through a named moment, which
    /// is the only origin that can carry either.
    private static func stop(
        _ technique: Technique,
        surface: DeliverySurface = .fullScreen,
        goal: TechniqueGoal? = nil,
        register: CopyRegister = .plain
    ) -> DialStop {
        guard surface == .discreet || goal != nil || register != .plain else {
            return DialStop(technique: technique, origin: .technique, band: .everything, saved: nil)
        }

        let occasion = Occasion(
            slug: "through-this-meeting",
            name: "Through this meeting",
            summary: "",
            prescription: Prescription(
                techniqueSlug: technique.slug,
                goal: goal ?? technique.goal,
                surface: surface,
                register: register,
                duration: .seconds(60)
            )
        )
        return DialStop(
            technique: technique,
            origin: .occasion(occasion),
            band: .occasions,
            saved: nil
        )
    }

    @Test("An unlocked full-screen stop states its goal and its length, and nothing else")
    func theTwoFactsEveryCardCarries() {
        let facts = Self.stop(Self.technique()).facts(for: .free)

        #expect(facts == "relax · 1 min")
    }

    @Test("A stop this tier cannot open says so before the tap")
    func theLockIsSpelled() {
        let locked = Self.stop(Self.technique(requires: .plus))

        // The mark the board draws as a `lock.fill` glyph, in the words that
        // reach somebody who never sees it.
        #expect(locked.facts(for: .free) == "relax · 1 min · Plus")
        // And gone again for a tier that opens it — the sentence follows the
        // entitlement rather than the technique.
        #expect(locked.facts(for: .plus) == "relax · 1 min")
    }

    @Test("A stop only the wrist can deliver quietly says which device it needs")
    func theWristIsSpelled() {
        let discreet = Self.stop(Self.technique(), surface: .discreet)

        #expect(discreet.facts(for: .free) == "relax · 1 min · on your watch")
    }

    @Test("Both marks are stated, in the order the board draws them")
    func theTwoMarksKeepTheirOrder() {
        let both = Self.stop(Self.technique(requires: .plus), surface: .discreet)

        #expect(both.facts(for: .free) == "relax · 1 min · Plus · on your watch")
    }

    @Test("The goal is the one the stop wears, not the one the technique was filed under")
    func anOccasionsGoalWins() {
        let stop = Self.stop(Self.technique(goal: .calm), goal: .sleep)

        #expect(stop.facts(for: .free) == "sleep · 1 min")
    }

    @Test("The printed caption and the spoken sentence open with the same two facts")
    func theCaptionAndTheLabelAgree() {
        let stop = Self.stop(Self.technique(requires: .plus), surface: .discreet)

        // What a row prints under a title is what the label leads with, so one
        // exercise cannot read two ways on one screen.
        #expect(stop.basics == "relax · 1 min")
        #expect(stop.facts(for: .free).hasPrefix(stop.basics))
    }

    /// `DialStop.id(of:)` answers before a stop exists, which is what lets the
    /// composer and an exercise's own screen star one — and it derives the band
    /// from `Technique.origin`, where the factories derive it from which list
    /// the technique arrived in. Nothing makes those two agree, so this does.
    ///
    /// `HomeOffer` leans on the correspondence directly: it matches the
    /// catalogue against `ids(standingFor:)` *before* building a stop, so that
    /// resolving a star does not allocate a stop per exercise the app has ever
    /// shipped. The day the two answers part company, a star stops pinning
    /// anything and this is what says so.
    @Test("A standalone stop carries the id its own technique answers with")
    func everyStandaloneStopCarriesTheIdItsTechniqueAnswersWith() {
        let authored = Technique(
            id: "mine",
            slug: "mine",
            name: "My own square",
            summary: "",
            goal: .calm,
            stages: [Stage(phases: [Phase(kind: .inhale, duration: .seconds(4))], cycles: 1)],
            recommendedRounds: 1,
            origin: .personal
        )

        let stops = DialStop.standalone(SeededCatalogue.techniques, in: .everything, dialled: [:])
            + DialStop.standalone([authored], in: .yours, dialled: [:])

        for stop in stops {
            #expect(stop.id == DialStop.id(of: stop.technique))
            #expect(stop.id == DialStop.standingFor(stop.technique).id)
        }
    }

    @Test("The id of an exercise names the band its row lives in")
    func theIdOfATechniqueNamesItsBand() {
        #expect(
            DialStop.id(of: SeededCatalogue.technique("box-breathing"))
                == "everything/box-breathing"
        )
    }

    @Test("A protocol's mechanics name the exercise, the length, and the tap marks")
    func theMechanicsNameTheExercise() {
        let stop = Self.stop(Self.technique(requires: .plus), surface: .discreet, goal: .sleep)

        // The card is titled by the moment, so the exercise is stated here —
        // and the marks ride along in `facts(for:)`'s order.
        #expect(stop.mechanics(for: .free) == "Steady · 1 min · Plus · on your watch")
        #expect(stop.mechanics(for: .plus) == "Steady · 1 min · on your watch")
    }

    @Test("The playful register is named; the plain one never is")
    func onlyThePlayfulRegisterIsNamed() {
        let playful = Self.stop(Self.technique(), register: .playful)

        #expect(playful.mechanics(for: .free) == "Steady · 1 min · playful")
        #expect(Self.stop(Self.technique()).mechanics(for: .free) == "Steady · 1 min")
    }

    @Test("A row speaks its name and then its facts, marks included")
    func theSpokenLabelCarriesTheWholeRow() {
        let stop = Self.stop(Self.technique(requires: .plus), surface: .discreet)

        // The marks are glyphs to the eye and nothing at all to VoiceOver, so
        // this is where a locked, wrist-only stop says so before the tap.
        // The occasion's name rather than the technique's, which is the same
        // rule the printed title follows — a stop is spoken as what it is.
        #expect(
            stop.spokenLabel(for: .free)
                == "Through this meeting, relax · 1 min · Plus · on your watch"
        )
    }
}
