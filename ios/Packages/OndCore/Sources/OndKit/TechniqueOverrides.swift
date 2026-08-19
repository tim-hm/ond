import Foundation

/// The dials applied to one stage of a technique.
///
/// Durations and cycles travel together so a caller cannot change one stage's
/// cycle count while indexing a separate collection for its phases.
public struct StageDialling: Sendable, Codable, Hashable {
    /// Phase durations in milliseconds, in the stage's authored order.
    public var phaseDurationsMs: [Int]
    /// How many times the stage's phase list plays.
    public var cycles: Int

    /// - Parameters:
    ///   - phaseDurationsMs: The stage's phase durations in authored order.
    ///   - cycles: How many times the phase list plays.
    public init(phaseDurationsMs: [Int], cycles: Int) {
        self.phaseDurationsMs = phaseDurationsMs
        self.cycles = cycles
    }
}

/// A person's dialled-in version of a technique.
///
/// Stored on the device and staying there. Profiles have shipped and these did
/// not move onto one: a dialled phase length is how a session feels in the room
/// it is done in, and `WatchSettings` already treats the wrist's one switch the
/// same way.
public struct TechniqueOverrides: Sendable, Codable, Hashable {
    /// Each stage's phase durations and cycle count, in authored order.
    public var stages: [StageDialling]
    /// How many times the whole stage list repeats.
    public var rounds: Int

    /// - Parameters:
    ///   - stages: Dialling for each stage in authored order.
    ///   - rounds: How many times the whole stage list repeats.
    public init(stages: [StageDialling], rounds: Int) {
        self.stages = stages
        self.rounds = rounds
    }

    /// Current keys plus the two legacy parallel-array keys accepted on decode.
    private enum CodingKeys: String, CodingKey {
        /// Stage-shaped dialling written by current releases.
        case stages
        /// Whole-technique repetitions in both representations.
        case rounds
        /// Legacy per-stage phase durations.
        case phaseDurationsMs
        /// Legacy cycle counts aligned with `phaseDurationsMs`.
        case stageCycles
    }

    /// Reads the stage-shaped representation, or the two aligned arrays older
    /// releases persisted.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        rounds = try container.decode(Int.self, forKey: .rounds)

        if let stages = try container.decodeIfPresent([StageDialling].self, forKey: .stages) {
            self.stages = stages
            return
        }

        let durations = try container.decode([[Int]].self, forKey: .phaseDurationsMs)
        let cycles = try container.decode([Int].self, forKey: .stageCycles)
        guard durations.count == cycles.count else {
            throw DecodingError.dataCorruptedError(
                forKey: .stageCycles,
                in: container,
                debugDescription: "legacy phase durations and cycles have different stage counts"
            )
        }
        stages = zip(durations, cycles).map { durations, cycles in
            StageDialling(phaseDurationsMs: durations, cycles: cycles)
        }
    }

    /// Writes only the stage-shaped representation so the next successful save
    /// completes migration from the legacy arrays.
    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(stages, forKey: .stages)
        try container.encode(rounds, forKey: .rounds)
    }

    /// How far a cycle count may be dialled.
    ///
    /// A constant rather than seeded data, unlike a phase duration: a cycle
    /// count has no evidence-based ceiling, only a point past which the number
    /// stops describing a session anyone will finish.
    public static let cycleRange = 1 ... 99
    /// How far a round count may be dialled. Tighter than the cycles, because
    /// rounds only exist in staged protocols and those are the demanding ones.
    public static let roundRange = 1 ... 10
}

public extension Technique {
    /// This technique exactly as the catalogue curated it — the starting point
    /// every dial moves away from, and what a reset returns to.
    var curatedOverrides: TechniqueOverrides {
        TechniqueOverrides(
            stages: stages.map { stage in
                StageDialling(
                    phaseDurationsMs: stage.phases.map { Int($0.duration.milliseconds) },
                    cycles: stage.cycles
                )
            },
            rounds: recommendedRounds
        )
    }

    /// `overrides` if they still describe this technique, the curated settings
    /// otherwise.
    ///
    /// The one place a stored preference is admitted. Everything downstream —
    /// the dials that index these arrays, the session that plays them — works
    /// from the result, so nothing can index a shape the catalogue has since
    /// changed.
    func resolving(_ overrides: TechniqueOverrides?) -> TechniqueOverrides {
        guard let overrides, fits(overrides) else { return curatedOverrides }
        return overrides
    }

    /// This technique as `overrides` dial it: the same catalogue entry, playing
    /// the durations, cycles, and rounds this person chose.
    ///
    /// Returns a `Technique` rather than a pair of values so that stages and
    /// rounds cannot be applied inconsistently — a session built from dialled
    /// stages and a curated round count is a session nobody asked for. Every
    /// value is clamped into the range the catalogue seeded, so a stored
    /// preference cannot outlive a tightened safe range.
    func dialled(with overrides: TechniqueOverrides?) -> Technique {
        let overrides = resolving(overrides)

        let stages = stages.enumerated().map { index, stage in
            let dialling = overrides.stages[index]
            return Stage(
                phases: stage.phases.enumerated().map { phaseIndex, phase in
                    phase.dialled(to: .milliseconds(dialling.phaseDurationsMs[phaseIndex]))
                },
                cycles: TechniqueOverrides.cycleRange.clamping(dialling.cycles),
                openEnded: stage.openEnded
            )
        }

        return replacing(
            stages: stages,
            recommendedRounds: TechniqueOverrides.roundRange.clamping(overrides.rounds)
        )
    }

    /// `saved` — or the curated dials where there are none — with the cycle
    /// count moved so one round of this technique lasts about `duration`.
    ///
    /// The person's phases win: a Box Breathing dialled to six-second sides
    /// fits fewer cycles into five minutes than the curated four-second one,
    /// and the length asked for is a length of *their* breath. Only cyclic
    /// exercises fit — a staged or open-ended technique comes back exactly as
    /// dialled, because its length is its shape — and the cycle count is
    /// clamped into `TechniqueOverrides.cycleRange`, so a two-second bellows
    /// cycle cannot honour ten minutes. Callers print the duration the result
    /// actually plays, never the one they asked for.
    ///
    /// A value to hand to `DialStop.standingFor(_:dialled:)` rather than a
    /// technique, so the fit rides the same road every other dial does and
    /// nothing here is persisted.
    func overrides(
        fitting duration: Duration,
        over saved: TechniqueOverrides? = nil
    ) -> TechniqueOverrides {
        var overrides = resolving(saved)
        guard isCyclic, let stage = dialled(with: overrides).stages.first else { return overrides }

        let wanted = Double(duration.milliseconds) / Double(stage.cycleDuration.milliseconds)
        overrides.stages[0].cycles = TechniqueOverrides.cycleRange.clamping(Int(wanted.rounded()))
        overrides.rounds = 1
        return overrides
    }

    /// Whether `overrides` still describes this technique's shape.
    private func fits(_ overrides: TechniqueOverrides) -> Bool {
        guard overrides.stages.count == stages.count else { return false }

        return zip(stages, overrides.stages).allSatisfy { stage, dialling in
            stage.phases.count == dialling.phaseDurationsMs.count
        }
    }
}

extension ClosedRange {
    /// `value`, brought inside the range.
    func clamping(_ value: Bound) -> Bound {
        Swift.min(Swift.max(value, lowerBound), upperBound)
    }
}
