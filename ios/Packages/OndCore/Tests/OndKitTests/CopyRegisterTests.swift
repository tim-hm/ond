import Foundation
@testable import OndKit
import Testing

/// The words a route asks a session to speak in. The register is the one
/// thing an occasion carries that changes what a person hears rather than
/// what they breathe. What these pin is that it covers the breaths it was
/// written for, says the plain thing everywhere else, and says the same
/// thing on the screen as in the ear.
@Suite("Which words a route speaks in")
struct CopyRegisterTests {
    @Test("Breathing Together is a protocol, not a catalogue exercise")
    func breathingTogetherIsNotAStandaloneExercise() {
        #expect(!SeededCatalogue.techniques.contains { $0.slug == "breathing-together" })
    }

    /// The two breaths the playful register was written for, and the whole of
    /// what it claims. Both forms, because a phrase has no passage to drop.
    @Test("The playful register renames the breaths it was written for")
    func thePlayfulRegisterRenamesItsOwnBreaths() {
        #expect(Breath.inhale(through: .nose).instruction(in: .playful) == "Smell the flower")
        #expect(Breath.exhale(through: .nose).instruction(in: .playful) == "Blow out the candle")
        #expect(
            Breath.inhale(through: .nose).writtenInstruction(in: .playful) == "Smell the flower"
        )
        #expect(
            Breath.exhale(through: .nose).writtenInstruction(in: .playful) == "Blow out the candle"
        )
    }

    /// Everything else keeps the plain sentence in both forms.
    ///
    /// The seeded route is held to nose-only breathing on the server, so this is
    /// unreachable from the catalogue today. It stays total anyway: a coach offer
    /// or an authored exercise could put any breath in front of it.
    @Test("Every other breath keeps the words it already had")
    func everythingElseFallsBackToPlain() {
        let unwritten = Breath.allCases.filter {
            $0 != .inhale(through: .nose) && $0 != .exhale(through: .nose)
        }

        for breath in unwritten {
            #expect(
                breath.instruction(in: .playful) == breath.instruction,
                "\(breath) should keep its plain sentence"
            )
            #expect(
                breath.writtenInstruction(in: .playful) == breath.kind.instruction,
                "\(breath) should keep its plain screen words"
            )
        }
    }

    /// The regression that made the screen form a `Breath` question rather than
    /// a `PhaseKind` one. Deriving the words through the nose is sound for plain
    /// wording and wrong for every other passage once a register covers only
    /// some: it put "Blow out the candle" over a mouth exhale whose spoken form
    /// correctly fell back, so one session said two things about one breath.
    @Test("A breath the register does not cover says one thing, not two")
    func theScreenAndTheEarAgreeOnAnUncoveredBreath() {
        let mouth = Breath.exhale(through: .mouth)

        #expect(mouth.writtenInstruction(in: .playful) == "Breathe out")
        #expect(mouth.instruction(in: .playful) == "Breathe out through your mouth")
    }

    /// The plain register changes nothing at all — the check that this was a
    /// layer over the wording rather than a rewrite of it.
    @Test("The plain register says exactly what the app said before it existed")
    func thePlainRegisterIsUnchanged() {
        for breath in Breath.allCases {
            #expect(breath.instruction(in: .plain) == breath.instruction)
            #expect(breath.writtenInstruction(in: .plain) == breath.kind.instruction)
        }
    }

    /// The register reaches the beats a session is played from, which is what
    /// makes the screen, VoiceOver, the watch and the Live Activity say one
    /// thing rather than four.
    @Test("A session laid out in a register says every beat in it")
    func theRegisterReachesEveryBeat() throws {
        let together = Prescription(
            techniqueSlug: "extended-exhale",
            goal: .calm,
            surface: .fullScreen,
            register: .playful,
            duration: .seconds(90),
            phaseDurations: [.seconds(3), .seconds(5)]
        ).dialled(SeededCatalogue.technique("extended-exhale"))
        let timeline = SessionTimeline(technique: together, register: .playful)

        #expect(timeline.register == .playful)

        let opening = try #require(timeline.beats.first)
        #expect(opening.instruction == "Smell the flower")
        #expect(opening.spokenInstruction == "Smell the flower")

        let out = try #require(timeline.beats.first { $0.kind == .exhale })
        #expect(out.instruction == "Blow out the candle")

        #expect(timeline.beats.allSatisfy { $0.register == timeline.register })
    }

    /// Every register settles somebody in words of its own, so a countdown
    /// cannot render a blank heading over a counting numeral. Asserted as
    /// difference plus non-emptiness: wording is a copy decision free to move,
    /// but a register silently inheriting another's lines does nothing at the
    /// one moment it introduces itself.
    @Test("Every register has its own words for the countdown")
    func everyRegisterSettlesSomebodyIn() {
        for register in CopyRegister.allCases {
            #expect(!register.settlingLine.isEmpty)
            #expect(!register.countdownLine.isEmpty)
        }

        #expect(CopyRegister.playful.settlingLine != CopyRegister.plain.settlingLine)
        #expect(CopyRegister.playful.countdownLine != CopyRegister.plain.countdownLine)
    }

    /// The exercise a child protocol uses still speaks plainly when reached
    /// without that route — the playful words belong to the protocol.
    @Test("The same exercise off the catalogue speaks plainly")
    func theCatalogueSpeaksPlainly() throws {
        let extended = SeededCatalogue.technique("extended-exhale")
        let timeline = SessionTimeline(technique: extended)

        let opening = try #require(timeline.beats.first)
        #expect(opening.instruction == "Breathe in")
        #expect(opening.register == .plain)
    }
}
