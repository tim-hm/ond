import Foundation

/// How the breath moves in one phase somebody is composing, and where the air
/// goes with it.
///
/// Three cases where `Breath` has four. Which of the two holds a hold is has
/// never been a choice — it follows from the breath before it — so the composer
/// offers one and `kind(after:)` resolves it, which is the one part of the old
/// picker nobody should have had to think about.
///
/// The passage rides on the two moving cases for the reason it does on `Breath`:
/// a hold has no passage, and this is the shape in which saying otherwise is
/// impossible rather than refused.
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

    /// The `PhaseKind` this movement stores as, given the last breath before it
    /// anywhere in the draft.
    ///
    /// A hold after an inhale is held on full lungs and one after an exhale on
    /// empty; a hold with nothing before it at all is empty, because that is
    /// where a session starts. The server derives the same way and its answer is
    /// the one that is stored — this copy exists so the composer can show the
    /// dial the server will actually enforce.
    ///
    /// Every prior breath is named rather than compared against the inhale, and
    /// that is what the duplication is for: a fifth kind that moves air fails to
    /// compile on both sides until somebody says which hold follows it. Guessing
    /// would put the dial's range on the wrong safe duration and disagree with
    /// the server about what was stored.
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

/// One phase somebody is composing.
///
/// `Identifiable` on a minted id rather than on its position, because a composer
/// reorders and deletes: a `ForEach` keyed on an index moves the wrong row's
/// focus the moment anything before it changes. The id is never sent — the
/// server numbers phases by their position in the draft it receives.
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
/// belongs to the curated protocols that carry the copy explaining it, and the
/// contract has no way to author one.
///
/// `Identifiable` for the reason `DraftPhase` is, and a sharper one: a composer
/// that removes the middle stage of three renumbers the stages after it, so a
/// `ForEach` keyed on position would go on rendering bindings into a slot that
/// is now somebody else's. The id is never sent — the server numbers stages by
/// their position in the draft it receives.
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
///
/// Mutable where `Technique` is not, because this is what a composer's bindings
/// write into. It converts to a `Technique` only by being stored: what comes
/// back carries the id, the slug, and the safe ranges, none of which the person
/// composing owns.
public struct TechniqueDraft: Sendable, Hashable, Codable {
    public var name: String
    /// What they reach for it for, in their own words, or empty where they said
    /// nothing — which is ordinary and is what a blank composer opens on.
    ///
    /// Named for the field it becomes: the server stores it as
    /// `Technique.summary`, the same one the catalogue's curated sentence
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
    /// `[stage][phase]`.
    ///
    /// The whole draft at once rather than a phase at a time, because a hold
    /// reads back to the last breath before it — which may be in an earlier
    /// stage — so answering for one phase means walking the draft anyway. A
    /// composer reads it to pick the dial range for a row, and the server
    /// derives the same way when it stores the draft.
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
    /// as the blueprint for one of somebody's own.
    ///
    /// Beside the initialiser it guards rather than on the screen that offers
    /// the copy, because it is a precondition of the conversion and not a rule
    /// of any one surface — a second entry point that asked the question its own
    /// way is how the retention below gets flattened again. Here rather than in
    /// `Technique.swift` for `closingNote`'s reason too: it is a curation rule
    /// over the whole catalogue, and the app target has no test bundle.
    ///
    /// Somebody's own exercise is edited instead; only the catalogue is a
    /// blueprint. A stage the person ends is excluded outright, for the reason
    /// stated on the initialiser.
    var isCopyable: Bool {
        origin == .catalogue && !hasOpenEndedStage
    }
}

public extension TechniqueDraft {
    /// The draft holding `technique`'s content — what Edit reopens, and what
    /// starting your own version of a curated exercise begins from.
    ///
    /// One initialiser for both because a draft is content and nothing else: it
    /// carries no id and no slug, so what comes back from saving one is decided
    /// entirely by whether the composer was handed something to replace. That is
    /// also what makes copying a catalogue entry safe — there is no identity on
    /// this value that could point an update at somebody else's row.
    ///
    /// Content and nothing else, so a copy arrives without the mechanism, the
    /// safety note, the preparation line, the per-phase manner, the subscription
    /// gate or the curated per-phase ranges. All of that is the catalogue's
    /// rather than the exercise's, and none of it is something the composer could
    /// carry.
    ///
    /// The manner is the one of those a copy is *worse* for losing, and it is
    /// recorded here rather than fixed: copy the cooling breath and you get an
    /// exercise that reads identically, draws identically, and has quietly
    /// stopped mentioning the tongue on every surface. `DraftPhase` has nowhere
    /// to put one — a manner is curated copy asserting how a shaped breath
    /// works, and the composer does not invite an author to assert physiology.
    /// Whoever fixes this should give `DraftPhase` a manner the composer shows
    /// and cannot edit, rather than refusing the copy: three good exercises would
    /// lose the affordance to protect a line of text.
    ///
    /// A stage the person ends is the one loss this cannot absorb: `DraftStage`
    /// has no way to say so, and flattening one silently changes the protocol.
    /// `Technique.isCopyable` is what refuses those before they reach here.
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

/// What a composer is allowed to build, as the server states it.
///
/// Fetched rather than declared. The per-phase ranges are the catalogue's own
/// seeded evidence and the counts are the server's ceilings, so a client that
/// hardcoded either would be offering something the server may refuse — which is
/// a dial somebody drags to a number that then will not save.
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

    /// `draft` with every value brought inside these limits.
    ///
    /// The composer's own guard, and deliberately a clamp rather than a
    /// refusal: a dial cannot be dragged past its range, so the only way to
    /// arrive outside one is to have opened an exercise the seed has since
    /// narrowed under. The server checks these individual values again and
    /// additionally refuses a composition-wide hazard the downloaded limits
    /// cannot express: fast breathing anywhere in an authored exercise paired
    /// with a timed target hold anywhere in it. That server-only rule spans
    /// stages and rounds, so this client clamp cannot safely approximate it.
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
                // Indexed directly: `kinds` is derived from this same draft, so
                // the enumerated prefix indices cannot miss — and a guarded
                // miss fell into the same arm as a genuinely rangeless kind,
                // silently skipping the clamp if the derivation ever
                // misaligned. The guard is for `range(for:)` alone, whose nil
                // is a real state: a kind the catalogue never uses.
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
