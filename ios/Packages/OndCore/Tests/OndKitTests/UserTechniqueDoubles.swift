import Foundation
import OndKit
import Testing

/// The limits the server states, wide enough that a test can put a value
/// clearly inside or clearly outside one.
let limits = AuthoringLimits(
    phases: [
        PhaseLimit(kind: .inhale, range: .milliseconds(500) ... .milliseconds(10000)),
        PhaseLimit(kind: .exhale, range: .milliseconds(700) ... .milliseconds(12000)),
    ],
    maxNameChars: 60,
    maxSummaryChars: 500,
    maxStages: 4,
    maxPhasesPerStage: 8,
    cycleRange: 1 ... 99,
    roundRange: 1 ... 10,
    maxTechniques: 2
)

func draft(name: String = "Mine", summary: String = "") -> TechniqueDraft {
    TechniqueDraft(
        name: name,
        summary: summary,
        goal: .sleep,
        stages: [DraftStage(
            phases: [
                DraftPhase(movement: .inhale(through: .nose), duration: .milliseconds(4000)),
                DraftPhase(movement: .exhale(through: .nose), duration: .milliseconds(8000)),
            ],
            cycles: 10
        )]
    )
}

/// Two differently-shaped stages, twice over — the user-built equivalent of a
/// staged protocol, and the smallest draft that can have a seam in it. One second
/// in and one out, twice; then two in and three out, once; the whole thing twice.
/// Every number is distinct so a beat landing in the wrong stage shows up as a
/// wrong duration rather than as a coincidence.
func sequence() -> TechniqueDraft {
    TechniqueDraft(
        name: "Wake, then settle",
        goal: .energy,
        stages: [
            DraftStage(
                phases: [
                    DraftPhase(movement: .inhale(through: .nose), duration: .milliseconds(1000)),
                    DraftPhase(movement: .exhale(through: .nose), duration: .milliseconds(1000)),
                ],
                cycles: 2
            ),
            DraftStage(
                phases: [
                    DraftPhase(movement: .inhale(through: .nose), duration: .milliseconds(2000)),
                    DraftPhase(movement: .exhale(through: .nose), duration: .milliseconds(3000)),
                ],
                cycles: 1
            ),
        ],
        rounds: 2
    )
}

/// Turns a draft into what the server would return for it: the same `Technique`
/// message the catalogue serves, with the ranges stamped on and each hold's
/// lungs state derived — which is exactly the resolution the server performs.
func stored(_ draft: TechniqueDraft, id: String) -> Technique {
    Technique(
        id: id,
        slug: "own-\(id)",
        name: draft.name,
        summary: draft.summary,
        goal: draft.goal,
        stages: zip(draft.stages, draft.kinds).map { stage, kinds in
            Stage(
                phases: zip(stage.phases, kinds).map { phase, kind in
                    Phase(
                        kind: kind,
                        through: phase.movement.passage ?? .nose,
                        duration: phase.duration,
                        range: limits.range(for: kind) ?? phase.duration ... phase.duration
                    )
                },
                cycles: stage.cycles
            )
        },
        recommendedRounds: draft.rounds,
        origin: .personal
    )
}

/// Stands in for the server, counting calls so a test can tell a patched list
/// from a refetched one.
actor FakeStore: UserTechniqueStoring, UserTechniqueReading {
    private var techniques: [Technique] = []
    private var local: UserTechniqueList?
    private(set) var lists = 0
    var refusal: UserTechniqueRepositoryError?

    /// - Parameters:
    ///   - refusal: what every write throws, for the refusal paths.
    ///   - local: what this device is pretending to already hold, for the tests
    ///     about a failed refresh leaving a drawn list standing.
    init(
        refusing refusal: UserTechniqueRepositoryError? = nil,
        local: UserTechniqueList? = nil
    ) {
        self.refusal = refusal
        self.local = local
    }

    func localUserTechniques() async -> UserTechniqueList? {
        local
    }

    func listUserTechniques() async throws -> UserTechniqueList {
        lists += 1
        if let refusal {
            throw refusal
        }
        return UserTechniqueList(techniques: techniques, limits: limits)
    }

    func createUserTechnique(_ draft: TechniqueDraft) async throws -> Technique {
        if let refusal {
            throw refusal
        }
        let technique = stored(draft, id: "id-\(techniques.count)")
        techniques.append(technique)
        return technique
    }

    func updateUserTechnique(
        id: UserTechniqueId,
        to draft: TechniqueDraft
    ) async throws -> Technique {
        if let refusal {
            throw refusal
        }
        return stored(draft, id: id.value)
    }

    func deleteUserTechnique(id: UserTechniqueId) async throws {
        if let refusal {
            throw refusal
        }
        techniques.removeAll { $0.id == id.value }
    }

    func refuse(with error: UserTechniqueRepositoryError) {
        refusal = error
    }
}
