import Foundation
import OndAPI
@testable import OndKit
import Testing

@Suite("Decoding proto techniques into domain types")
struct TechniqueDecodingTests {
    private static func phase(
        _ kind: Ond_V1_PhaseKind,
        _ ms: UInt32,
        range: (UInt32, UInt32)? = nil,
        passage: Ond_V1_Passage = .nose
    ) -> Ond_V1_Phase {
        var phase = Ond_V1_Phase()
        phase.kind = kind
        phase.durationMs = ms
        phase.minDurationMs = range?.0 ?? ms
        phase.maxDurationMs = range?.1 ?? ms
        phase.passage = passage
        return phase
    }

    private static func stage(
        _ phases: [Ond_V1_Phase],
        cycles: UInt32 = 8,
        openEnded: Bool = false
    ) -> Ond_V1_Stage {
        var stage = Ond_V1_Stage()
        stage.phases = phases
        stage.cycles = cycles
        stage.openEnded = openEnded
        return stage
    }

    /// Nil `stages` means the plain one-stage shape most of these tests want;
    /// spelling it here rather than in a default argument keeps the fixture
    /// readable and unambiguous.
    private func protoTechnique(
        goal: Ond_V1_TechniqueGoal = .calm,
        stages: [Ond_V1_Stage]? = nil,
        recommendedRounds: UInt32 = 1,
        safetyNote: String = "",
        evidence: String = ""
    ) -> Ond_V1_Technique {
        var technique = Ond_V1_Technique()
        technique.id = "id"
        technique.slug = "box-breathing"
        technique.name = "Box Breathing"
        technique.summary = "Four equal counts."
        technique.goal = goal
        technique.stages = stages
            ?? [Self.stage([Self.phase(.inhale, 4000), Self.phase(.exhale, 4000)])]
        technique.recommendedRounds = recommendedRounds
        technique.safetyNote = safetyNote
        technique.evidence = evidence
        return technique
    }

    @Test("A well-formed technique decodes with its stages intact")
    func decodesAWellFormedTechnique() throws {
        let technique = try Technique(
            proto: protoTechnique(
                stages: [
                    Self.stage(
                        [Self.phase(.inhale, 4000, range: (3000, 8000)), Self.phase(.exhale, 4000)],
                        cycles: 8
                    ),
                    Self.stage([Self.phase(.holdOut, 60000)], cycles: 1, openEnded: true),
                ],
                recommendedRounds: 3
            )
        )

        #expect(technique.slug == "box-breathing")
        #expect(technique.goal == .calm)
        #expect(technique.stages.count == 2)
        #expect(technique.stages[0].cycles == 8)
        #expect(technique.stages[0].cycleDuration == .milliseconds(8000))
        #expect(technique.stages[1].openEnded)
        #expect(technique.recommendedRounds == 3)
        #expect(technique.hasOpenEndedStage)
        #expect(technique.safetyNote == nil, "an empty note is no note, not an empty one")
    }

    /// The dial is rendered from the range, so it has to arrive as authored
    /// rather than as a copy of the default — the whole point of seeding it.
    @Test("A phase carries the range its dial moves within")
    func decodesADialRange() throws {
        let technique = try Technique(
            proto: protoTechnique(
                stages: [Self.stage([Self.phase(.exhale, 6000, range: (6000, 8000))])]
            )
        )
        let exhale = try #require(technique.stages.first?.phases.first)

        #expect(exhale.range == .milliseconds(6000) ... .milliseconds(8000))
        #expect(exhale.isAdjustable)
        #expect(exhale.dialled(to: .milliseconds(12000)).duration == .milliseconds(8000))
    }

    /// A range that does not contain its own default leaves a slider with
    /// nowhere to put the handle, and a repaired one would be a safe limit this
    /// app invented. Same rule as the enums: reject rather than guess.
    @Test("A phase outside its own range is rejected")
    func rejectsAPhaseOutsideItsRange() {
        #expect(throws: TechniqueRepositoryError.self) {
            try Technique(
                proto: protoTechnique(
                    stages: [Self.stage([Self.phase(.inhale, 4000, range: (5000, 8000))])]
                )
            )
        }
    }

    /// Zero is the proto default, so it is what a server predating the field
    /// sends — and a session of no rounds has nothing to play.
    @Test("A technique recommending no rounds is rejected")
    func rejectsAZeroRoundCount() {
        #expect(throws: TechniqueRepositoryError.self) {
            try Technique(proto: protoTechnique(recommendedRounds: 0))
        }
    }

    @Test("A stage playing no cycles is rejected")
    func rejectsAZeroCycleStage() {
        #expect(throws: TechniqueRepositoryError.self) {
            try Technique(
                proto: protoTechnique(stages: [Self.stage([Self.phase(.inhale, 4000)], cycles: 0)])
            )
        }
    }

    /// The proto zero value is reachable from any server, including one running
    /// a newer contract. Decoding it as a real goal would put a technique in the
    /// wrong section of the catalogue with nothing to indicate it.
    @Test("An unspecified goal is rejected rather than defaulted")
    func rejectsAnUnspecifiedGoal() {
        #expect(throws: TechniqueRepositoryError.self) {
            try Technique(proto: protoTechnique(goal: .unspecified))
        }
    }

    /// The phase twin of the goal test above — same boundary, same rule.
    @Test("An unspecified phase kind is rejected rather than defaulted")
    func rejectsAnUnspecifiedPhaseKind() {
        #expect(throws: TechniqueRepositoryError.self) {
            try Technique(
                proto: protoTechnique(stages: [Self.stage([Self.phase(.unspecified, 4000)])])
            )
        }
    }

    /// A technique with no stages — or a stage with no phases — would leave the
    /// player with an empty loop and no segment to advance to.
    @Test("A technique with nothing to play is rejected")
    func rejectsATechniqueWithNothingToPlay() {
        #expect(throws: TechniqueRepositoryError.self) {
            try Technique(proto: protoTechnique(stages: []))
        }
        #expect(throws: TechniqueRepositoryError.self) {
            try Technique(proto: protoTechnique(stages: [Self.stage([])]))
        }
    }

    /// The second-order hazard is what makes this a refusal rather than the
    /// degrade beside it: an exercise somebody composed decodes through this
    /// same initialiser, `TechniqueDraft(copying:)` rebuilds a draft from what
    /// came out, and saving that edit would write this build's guess back over
    /// the passage they chose. A decode that fails is what puts that path out
    /// of reach — on both services, since both land here.
    @Test("A passage this build cannot name is refused rather than read as the nose")
    func rejectsAnUnrecognisedPassage() {
        let unknown = protoTechnique(
            stages: [Self.stage([Self.phase(.inhale, 4000, passage: .UNRECOGNIZED(9))])]
        )

        #expect(throws: TechniqueRepositoryError.self) {
            try Technique(proto: unknown)
        }
        #expect(throws: TechniqueRepositoryError.self) {
            try Technique(authored: unknown)
        }
    }

    /// The half of the passage contract that stays lenient: an unset field is
    /// what a server predating it sends, and the nose is what eight of the
    /// eleven seeded techniques breathe through — so this one degrades where the
    /// unrecognised case above refuses.
    @Test("A breath with no passage set is read as the nose")
    func degradesAnUnsetPassageToTheNose() throws {
        let technique = try Technique(
            proto: protoTechnique(
                stages: [Self.stage([Self.phase(.exhale, 4000, passage: .unspecified)])]
            )
        )

        #expect(technique.stages[0].phases[0].breath == .exhale(through: .nose))
    }

    /// A hold has nowhere to put a passage, so it never reads the field — which
    /// is what keeps `UNSPECIFIED`, the value a hold is contracted to carry,
    /// from being read as a gap in the first place.
    @Test("A hold ignores the passage the wire carries beside it")
    func aHoldDropsItsPassage() throws {
        let technique = try Technique(
            proto: protoTechnique(
                stages: [Self.stage([
                    Self.phase(.holdOut, 4000, passage: .unspecified),
                    Self.phase(.holdIn, 4000, passage: .UNRECOGNIZED(9)),
                ])]
            )
        )

        #expect(technique.stages[0].phases.map(\.passage) == [nil, nil])
    }

    @Test("Safety copy survives the trip")
    func decodesTheSafetyNote() throws {
        let technique = try Technique(proto: protoTechnique(safetyNote: "Never in water."))
        #expect(technique.safetyNote == "Never in water.")
    }

    /// The wire half of the evidence footnote, which the bundled export's own
    /// test cannot reach: a server that stopped sending the field, or a proto
    /// renumbering that moved it, would leave every technique looking exactly
    /// like one nobody has written about — and the empty a technique without one
    /// carries has to arrive as nothing rather than as a blank paragraph.
    @Test("Evidence copy survives the trip, and an empty one arrives as nothing")
    func decodesTheEvidenceNote() throws {
        let written = try Technique(proto: protoTechnique(evidence: "One small trial."))
        #expect(written.evidence == "One small trial.")

        let silent = try Technique(proto: protoTechnique())
        #expect(silent.evidence == nil)
    }

    @Test("Every domain goal has a display title")
    func everyGoalHasATitle() {
        for goal in TechniqueGoal.allCases {
            #expect(!goal.title.isEmpty)
        }
    }
}
