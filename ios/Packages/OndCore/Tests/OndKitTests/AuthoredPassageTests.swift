import Foundation
import OndKit
import Testing

/// Alternate-nostril breathing as somebody would compose it — the exercise the
/// passage exists for, and the one the composer could not reach at all before
/// the field was on the wire.
private func alternateNostril() -> TechniqueDraft {
    TechniqueDraft(
        name: "Nadi shodhana, mine",
        goal: .focus,
        stages: [DraftStage(
            phases: [
                DraftPhase(movement: .inhale(through: .leftNostril), duration: .seconds(4)),
                DraftPhase(movement: .exhale(through: .rightNostril), duration: .seconds(6)),
                DraftPhase(movement: .inhale(through: .rightNostril), duration: .seconds(4)),
                DraftPhase(movement: .exhale(through: .leftNostril), duration: .seconds(6)),
            ],
            cycles: 9
        )]
    )
}

/// What the server would answer with for `draft`: the same `Technique` message
/// the catalogue serves, with each hold's lungs state derived — which is exactly
/// the resolution the server performs on the way into the tables.
private func stored(_ draft: TechniqueDraft) -> Technique {
    Technique(
        id: "id",
        slug: "own-id",
        name: draft.name,
        summary: "",
        goal: draft.goal,
        stages: zip(draft.stages, draft.kinds).map { stage, kinds in
            Stage(
                phases: zip(stage.phases, kinds).map { phase, kind in
                    Phase(
                        kind: kind,
                        through: phase.movement.passage ?? .nose,
                        duration: phase.duration
                    )
                },
                cycles: stage.cycles
            )
        },
        recommendedRounds: draft.rounds,
        origin: .personal
    )
}

/// The composer offers three movements and the contract stores four kinds. This
/// is the derivation that closes the gap, and it has to agree with the server's
/// — they are two implementations of one rule across a language boundary.
@Suite("Deriving which hold a hold is")
struct MovementTests {
    @Test("A hold takes its lungs state from the breath before it")
    func derivesAcrossTheWholeDraft() {
        var boxed = TechniqueDraft(
            name: "Mine",
            goal: .calm,
            stages: [DraftStage(
                phases: [
                    DraftPhase(movement: .hold, duration: .seconds(4)),
                    DraftPhase(movement: .inhale(through: .nose), duration: .seconds(4)),
                    DraftPhase(movement: .hold, duration: .seconds(4)),
                    DraftPhase(movement: .exhale(through: .nose), duration: .seconds(4)),
                    DraftPhase(movement: .hold, duration: .seconds(4)),
                ],
                cycles: 1
            )]
        )
        boxed.stages.append(DraftStage(
            phases: [DraftPhase(movement: .hold, duration: .seconds(4))],
            cycles: 1
        ))

        #expect(boxed.kinds == [
            // Nothing before it: a session starts on empty lungs.
            [.holdOut, .inhale, .holdIn, .exhale, .holdOut],
            // The lungs state carries across the stage boundary, as the session
            // plays it.
            [.holdOut],
        ])
    }

    @Test("Editing a stored exercise forgets the lungs state and puts it back")
    func roundTripsAHold() {
        let boxed = Technique(
            id: "id",
            slug: "own-id",
            name: "Mine",
            summary: "",
            goal: .calm,
            stages: [Stage(
                phases: [
                    Phase(kind: .inhale, duration: .seconds(4)),
                    Phase(kind: .holdIn, duration: .seconds(4)),
                    Phase(kind: .exhale, duration: .seconds(4)),
                    Phase(kind: .holdOut, duration: .seconds(4)),
                ],
                cycles: 1
            )],
            recommendedRounds: 1,
            origin: .personal
        )

        let editing = TechniqueDraft(editing: boxed)

        #expect(editing.stages[0].phases.map(\.movement) == [
            .inhale(through: .nose), .hold, .exhale(through: .nose), .hold,
        ])
        #expect(editing.kinds == [[.inhale, .holdIn, .exhale, .holdOut]])
    }

    /// A hold has nowhere to put a passage — in the draft, in the stored breath,
    /// and on the wire between them. This is that claim held against the two
    /// conversions, which are the only places it could be lost.
    @Test("A hold carries no passage through either conversion")
    func aHoldHasNoPassage() {
        #expect(Movement.hold.passage == nil)
        #expect(Movement.hold.through(.leftNostril) == .hold)
        #expect(Breath(kind: .holdIn, through: .leftNostril).passage == nil)
        #expect(Breath(kind: .holdIn, through: .leftNostril) == .holdIn)
    }
}

/// The clause the whole issue turns on: an authored alternate-nostril exercise
/// draws alternating, exactly as the seeded one does.
///
/// It could not before, because the sides came from a table keyed on the
/// *catalogue's* slug — so a technique somebody wrote was invisible to it
/// however faithfully they wrote it. The sides come off the phases now, and
/// nothing in this suite names a seeded slug.
@Suite("Drawing an exercise somebody wrote")
struct AuthoredFigureTests {
    @Test("An authored alternate-nostril exercise draws on alternating sides")
    func authoredNostrilsDrawAlternating() throws {
        let mine = stored(alternateNostril())
        let stage = try #require(mine.stages.first)

        #expect(stage.signedPhases?.map(\.side) == [.left, .left, .right, .right])

        let figure = try #require(TechniqueFigure.all(for: mine).first)

        #expect(
            figure.description.contains("left nostril"),
            "the spoken description names the nostrils it was authored with"
        )
        #expect(
            figure.labels.contains { $0.text.hasSuffix("L") },
            "the figure marks which nostril each breath is"
        )
        #expect(
            figure.labels.contains { $0.text.hasSuffix("R") },
            "both sides are named, not only the one the cycle opens on"
        )
    }

    /// The letters are the alternation's whole presence on the figure — the
    /// shape draws fullness, not sides — so an exercise with no nostrils to
    /// alternate between must not acquire them.
    @Test("An exercise composed through the nose stays one-sided")
    func nasalBreathingHasNoSides() {
        var nasal = alternateNostril()
        nasal.stages[0].phases = nasal.stages[0].phases.map { phase in
            var phase = phase
            phase.movement = phase.movement.through(.nose)
            return phase
        }

        #expect(stored(nasal).stages[0].signedPhases == nil)
    }

    /// The nose is what seven of the nine seeded techniques do throughout, so
    /// naming it on every breath of every exercise would be noise in the one
    /// line that has to be readable when it is not.
    @Test("Only a passage worth saying is said")
    func onlyANotablePassageIsHinted() {
        #expect(Passage.nose.hint == nil)
        #expect(Passage.mouth.hint == "Mouth")
        #expect(Passage.leftNostril.hint == "Left nostril")

        #expect(Breath.inhale(through: .nose).instruction == "Breathe in")
        #expect(
            Breath.exhale(through: .rightNostril).instruction
                == "Breathe out through your right nostril"
        )
        #expect(Breath.holdOut.instruction == "Hold")
    }
}
