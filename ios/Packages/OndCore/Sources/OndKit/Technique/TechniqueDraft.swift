import Foundation

/// How the breath moves in one phase somebody is composing, and where the air
/// goes with it. Three cases where `Breath` has four: which of the two holds a
/// hold is follows from the breath before it, so the composer offers one and
/// `kind(after:)` resolves it. The passage rides on the two moving cases, so a
/// hold with a passage is impossible rather than refused.
public enum Movement: Sendable, Hashable, Codable {
    case inhale(through: Passage)
    case hold
    case exhale(through: Passage)

    /// One of each, in the order a cycle runs, for a picker to render.
    ///
    /// Not `CaseIterable`: two of the three carry a passage, so any list of
    /// "every case" has to invent one. These carry the nose, which is where a
    /// new phase starts and what the row's own selector then changes.
    public static let options: [Self] = [.inhale(through: .nose), .hold, .exhale(through: .nose)]

    /// Where the air goes, or nil for a hold.
    public var passage: Passage? {
        switch self {
        case let .inhale(passage), let .exhale(passage): passage
        case .hold: nil
        }
    }

    /// The same movement through `passage`, or unchanged for a hold — which has
    /// nowhere to put one.
    public func through(_ passage: Passage) -> Self {
        switch self {
        case .inhale: .inhale(through: passage)
        case .exhale: .exhale(through: passage)
        case .hold: .hold
        }
    }

    /// The `PhaseKind` this movement stores as, given the last breath before
    /// it in the draft: a hold after an inhale is on full lungs; after an
    /// exhale, or nothing, on empty. The server derives the same way and its
    /// answer is stored — this copy shows the dial the server will enforce.
    /// Every prior breath is named, so a new air-moving kind fails to compile.
    public func kind(after breath: PhaseKind?) -> PhaseKind {
        switch self {
        case .inhale: .inhale
        case .exhale: .exhale
        case .hold:
            switch breath {
            case .inhale: .holdIn
            case .exhale, .holdIn, .holdOut, .none: .holdOut
            }
        }
    }

    /// What to call it in a picker. The spoken form of the two holds is what
    /// distinguishes them, and this offers one hold, so there is nothing to
    /// distinguish.
    public var title: String {
        switch self {
        case .inhale: "Breathe in"
        case .hold: "Hold"
        case .exhale: "Breathe out"
        }
    }

    /// The movement that edits a stored breath — the direction that loses the
    /// hold's lungs state, which `kind(after:)` puts back.
    public init(_ breath: Breath) {
        switch breath {
        case let .inhale(passage): self = .inhale(through: passage)
        case let .exhale(passage): self = .exhale(through: passage)
        case .holdIn, .holdOut: self = .hold
        }
    }
}

/// One phase somebody is composing. `Identifiable` on a minted id, not its
/// position: a `ForEach` keyed on an index moves the wrong row's focus when
/// anything before it changes. The id is never sent — the server numbers
/// phases by their position in the draft it receives.
public struct DraftPhase: Sendable, Hashable, Codable, Identifiable {
    public let id: UUID
    public var movement: Movement
    public var duration: Duration

    public init(id: UUID = UUID(), movement: Movement, duration: Duration) {
        self.id = id
        self.movement = movement
        self.duration = duration
    }
}

/// One stage somebody is composing. No `openEnded`: a hold the person ends
/// belongs to the curated protocols, and the contract has no way to author
/// one. `Identifiable` on a minted id for `DraftPhase`'s reason — removing the
/// middle stage renumbers the rest, so a position-keyed `ForEach` would render
/// bindings into somebody else's slot. The id is never sent.
public struct DraftStage: Sendable, Hashable, Codable, Identifiable {
    public let id: UUID
    public var phases: [DraftPhase]
    public var cycles: Int

    public init(id: UUID = UUID(), phases: [DraftPhase], cycles: Int) {
        self.id = id
        self.phases = phases
        self.cycles = cycles
    }
}

/// A technique somebody is building, before the server has accepted it.
/// Mutable where `Technique` is not — a composer's bindings write into it. It
/// becomes a `Technique` only by being stored: what comes back carries the id,
/// the slug, and the safe ranges, none of which the composer owns.
public struct TechniqueDraft: Sendable, Hashable, Codable {
    public var name: String
    /// What they reach for it for, in their own words, or empty where they
    /// said nothing. Named for the field it becomes: the server stores it as
    /// `Technique.summary`, the same field the catalogue's curated sentence
    /// arrives in, so every screen that reads one reads the other.
    public var summary: String
    public var goal: TechniqueGoal
    /// The session, in play order.
    public var stages: [DraftStage]
    /// How many times the whole stage list repeats. One for a lone stage, where
    /// a round and a cycle would be the same number said twice — it is a
    /// sequence of differently-shaped stages that gives rounds something to say
    /// that cycles cannot.
    public var rounds: Int

    public init(
        name: String,
        summary: String = "",
        goal: TechniqueGoal,
        stages: [DraftStage],
        rounds: Int = 1
    ) {
        self.name = name
        self.summary = summary
        self.goal = goal
        self.stages = stages
        self.rounds = rounds
    }

    /// The `PhaseKind` every phase of this draft derives to, indexed
    /// `[stage][phase]`. The whole draft at once because a hold reads back to
    /// the last breath before it, which may sit in an earlier stage. The
    /// composer picks dial ranges from it; the server derives the same way.
    public var kinds: [[PhaseKind]] {
        var breath: PhaseKind?
        return stages.map { stage in
            stage.phases.map { phase in
                let kind = phase.movement.kind(after: breath)
                if !kind.isHold {
                    breath = kind
                }
                return kind
            }
        }
    }

    /// How long a session of this draft would take, for the composer to show
    /// while somebody is still deciding.
    public var plannedDuration: Duration {
        let perRound = stages.reduce(Duration.zero) { total, stage in
            total + stage.phases.reduce(.zero) { $0 + $1.duration } * max(stage.cycles, 1)
        }
        return perRound * max(rounds, 1)
    }
}

public extension Technique {
    /// Whether this exercise may be handed to ``TechniqueDraft/init(copying:)``
    /// as the blueprint for one of somebody's own. Beside the initialiser it
    /// guards because it is a precondition of the conversion, not a surface
    /// rule. Only the catalogue is a blueprint — your own exercise is edited —
    /// and a stage the person ends is excluded: flattening it changes the protocol.
    var isCopyable: Bool {
        origin == .catalogue && !hasOpenEndedStage
    }
}

public extension TechniqueDraft {
    /// The draft holding `technique`'s content — what Edit reopens, and what
    /// copying a curated exercise begins from. A draft carries no id or slug,
    /// so a copy cannot point an update at somebody else's row. The copy loses
    /// the per-phase manner, `DraftPhase` having nowhere to put one; fix by
    /// giving it a shown, uneditable manner rather than by refusing the copy.
    init(copying technique: Technique) {
        self.init(
            name: technique.name,
            summary: technique.summary,
            goal: technique.goal,
            stages: technique.stages.map { stage in
                DraftStage(
                    phases: stage.phases.map {
                        DraftPhase(movement: Movement($0.breath), duration: $0.duration)
                    },
                    cycles: stage.cycles
                )
            },
            rounds: technique.recommendedRounds
        )
    }
}

/// One phase kind, and how long a phase of it may be.
public struct PhaseLimit: Sendable, Equatable, Codable {
    public let kind: PhaseKind
    public let range: ClosedRange<Duration>

    public init(kind: PhaseKind, range: ClosedRange<Duration>) {
        self.kind = kind
        self.range = range
    }
}

/// What a composer is allowed to build, as the server states it. Fetched
/// rather than declared: the ranges are the catalogue's seeded evidence and
/// the counts the server's ceilings, so a client that hardcoded either would
/// offer a dial somebody drags to a number that then will not save.
public struct AuthoringLimits: Sendable, Equatable, Codable {
    /// In the order a cycle runs — inhale, hold, exhale, hold — which is the
    /// order a picker offers them in. A kind absent from this list cannot be
    /// authored at all.
    public let phases: [PhaseLimit]
    public let maxNameChars: Int
    public let maxSummaryChars: Int
    public let maxStages: Int
    public let maxPhasesPerStage: Int
    public let cycleRange: ClosedRange<Int>
    public let roundRange: ClosedRange<Int>
    public let maxTechniques: Int

    public init(
        phases: [PhaseLimit],
        maxNameChars: Int,
        maxSummaryChars: Int,
        maxStages: Int,
        maxPhasesPerStage: Int,
        cycleRange: ClosedRange<Int>,
        roundRange: ClosedRange<Int>,
        maxTechniques: Int
    ) {
        self.phases = phases
        self.maxNameChars = maxNameChars
        self.maxSummaryChars = maxSummaryChars
        self.maxStages = maxStages
        self.maxPhasesPerStage = maxPhasesPerStage
        self.cycleRange = cycleRange
        self.roundRange = roundRange
        self.maxTechniques = maxTechniques
    }

    /// How long a phase of `kind` may be, or nil for a kind with no seeded
    /// evidence behind any duration.
    public func range(for kind: PhaseKind) -> ClosedRange<Duration>? {
        phases.first { $0.kind == kind }?.range
    }

    /// `draft` with every value brought inside these limits. A clamp, not a
    /// refusal: a dial cannot pass its range, so the only way outside one is an
    /// exercise the seed has since narrowed under. The server checks again and
    /// alone refuses the hazard these limits cannot express — fast breathing
    /// paired with a timed target hold anywhere; that rule spans stages and rounds.
    public func clamping(_ draft: TechniqueDraft) -> TechniqueDraft {
        // Read off the draft as it arrived, before the truncations below can
        // shorten it: a phase's derived kind depends on the breaths ahead of it,
        // so re-deriving mid-clamp would answer for a draft nobody wrote.
        let kinds = draft.kinds

        var clamped = draft
        clamped.rounds = roundRange.clamping(draft.rounds)
        clamped.stages = draft.stages.prefix(maxStages).enumerated().map { index, stage in
            var stage = stage
            stage.cycles = cycleRange.clamping(stage.cycles)
            stage.phases = stage.phases.prefix(maxPhasesPerStage).enumerated().map { at, phase in
                // Indexed directly: `kinds` derives from this same draft, so
                // the prefix indices cannot miss — a guarded miss once fell
                // into the same arm as a rangeless kind and silently skipped
                // the clamp. The guard is for `range(for:)`'s real nil alone.
                guard let range = range(for: kinds[index][at]) else {
                    return phase
                }
                var phase = phase
                phase.duration = range.clamping(phase.duration)
                return phase
            }
            return stage
        }
        return clamped
    }
}
