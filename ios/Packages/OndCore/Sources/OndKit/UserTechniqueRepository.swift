import Foundation
import OndAPI

public enum UserTechniqueRepositoryError: LocalizedError, DiagnosticCarrying, Equatable {
    /// The RPC failed on something a later attempt may not hit — no network, a
    /// server that is down, an `UNAUTHENTICATED` a Keychain read may yet fix.
    ///
    /// Carries the classified outcome for the person and the transport's own
    /// words for the log — see [`TransportFault`].
    case transport(TransportFault)
    /// The server refused this draft and would refuse it again: a phase outside
    /// the seeded safe range, or one exercise more than a person may keep.
    ///
    /// Split from `.transport` for the reason `ProfileRepositoryError.rejected`
    /// is — retrying cannot mend it — and carries the server's own message,
    /// which names the phase it objected to.
    case rejected(String)
    /// The response parsed but described something this app cannot represent.
    case malformedResponse(String)

    /// What a person reads. Without this conformance `localizedDescription`
    /// bridges to a bare `NSError` and says "The operation couldn't be
    /// completed".
    ///
    /// A refusal keeps the server's own words: it names the phase it objected
    /// to, which is the one thing a composer can act on.
    public var errorDescription: String? {
        switch self {
        case let .transport(fault): fault.outcome.message
        case let .rejected(message): message
        case .malformedResponse: "This exercise arrived in a form the app couldn't read."
        }
    }

    /// What a log records — the transport's own words, kept off the screen.
    public var diagnostic: String {
        switch self {
        case let .transport(fault): fault.diagnostic
        case let .rejected(message): message
        case let .malformedResponse(message): "the response could not be read: \(message)"
        }
    }
}

/// One person's exercises, and the limits they may be composed within.
///
/// The limits travel with the list rather than being fetched separately: a
/// composer needs them before there is anything to list, which is exactly the
/// first launch this call covers.
public struct UserTechniqueList: Sendable, Equatable, Codable {
    public let techniques: [Technique]
    public let limits: AuthoringLimits

    public init(techniques: [Technique], limits: AuthoringLimits) {
        self.techniques = techniques
        self.limits = limits
    }
}

/// What this service knows an exercise by.
///
/// A type rather than a `String` because `Technique` carries an `id` and a
/// `slug` side by side, and everything else in the app — a session record, the
/// catalogue, the artwork — is keyed on the slug. Handing a slug to an edit or a
/// delete compiled, and surfaced only as a `NOT_FOUND` from the server. Same
/// discipline `UserId` establishes on the other side of the wire.
public struct UserTechniqueId: Sendable, Hashable {
    public let value: String

    /// Minted from the exercise itself and never from a loose string, so that
    /// reading the id rather than the slug happens exactly here.
    public init(of technique: Technique) {
        value = technique.id
    }
}

/// Reads and writes the exercises somebody composed for themselves.
///
/// The counterpart to `TechniqueReading`, kept separate for the reason the two
/// services are: one is reference data anybody may read, the other is one
/// person's own and needs their identity on every call.
public protocol UserTechniqueStoring: Sendable {
    func listUserTechniques() async throws -> UserTechniqueList
    func createUserTechnique(_ draft: TechniqueDraft) async throws -> Technique
    func updateUserTechnique(
        id: UserTechniqueId,
        to draft: TechniqueDraft
    ) async throws -> Technique
    func deleteUserTechnique(id: UserTechniqueId) async throws
}

/// Reads one person's composed exercises from this device and refreshes them.
///
/// The counterpart to `TechniqueReading`, and split from `UserTechniqueStoring`
/// for the reason that one is split from `ReferenceFetching`: fetching is what a
/// repository does, and answering from what the device already holds is what a
/// cache wraps around it. A model holds both, because a screen that lists
/// exercises is the same screen that composes them.
public protocol UserTechniqueReading: Sendable {
    /// The best list already on this device for whoever is signed in now, or
    /// nil before any fetch has succeeded under this identity.
    func localUserTechniques() async -> UserTechniqueList?
}

/// The only type that touches the generated user-technique types, mirroring
/// `TechniqueRepository`.
public struct UserTechniqueRepository: UserTechniqueStoring {
    private let client: Ond_V1_UserTechniqueServiceClient

    public init(baseURL: URL, identity: any UserIdentityStore) {
        client = OndClients.userTechniqueService(
            baseURL: baseURL,
            userId: identity.userId,
            sessionCredential: identity.sessionCredential
        )
    }

    public func listUserTechniques() async throws -> UserTechniqueList {
        let response = await client
            .listUserTechniques(request: Ond_V1_ListUserTechniquesRequest())

        guard let message = response.message else {
            throw Self.failure(refused: false, response.transportOutcome, response.error)
        }

        guard message.hasLimits else {
            throw UserTechniqueRepositoryError.malformedResponse(
                "the server sent no authoring limits"
            )
        }

        return try UserTechniqueList(
            techniques: message.techniques.map(Technique.init(authored:)),
            limits: AuthoringLimits(proto: message.limits)
        )
    }

    public func createUserTechnique(_ draft: TechniqueDraft) async throws -> Technique {
        var request = Ond_V1_CreateUserTechniqueRequest()
        request.draft = draft.proto

        let response = await client.createUserTechnique(request: request)

        guard let message = response.message else {
            // The two ways a create is refused rather than merely failed: a
            // phase outside the seeded safe range (`invalidArgument`), and one
            // exercise past the number a person may keep (`failedPrecondition`).
            // The throttle's `resourceExhausted` is deliberately absent — that
            // refusal is about the minute, not the draft, and falls through to
            // `.transport` so a retry stays on the table.
            let refused = response.code == .invalidArgument
                || response.code == .failedPrecondition
            throw Self.failure(refused: refused, response.transportOutcome, response.error)
        }

        return try Technique(authored: message.technique)
    }

    public func updateUserTechnique(
        id: UserTechniqueId,
        to draft: TechniqueDraft
    ) async throws -> Technique {
        var request = Ond_V1_UpdateUserTechniqueRequest()
        request.id = id.value
        request.draft = draft.proto

        let response = await client.updateUserTechnique(request: request)

        guard let message = response.message else {
            // `notFound` is a refusal rather than a fault: the exercise was
            // deleted on another device, and retrying reaches for a row that
            // will never come back.
            let refused = response.code == .invalidArgument || response.code == .notFound
            throw Self.failure(refused: refused, response.transportOutcome, response.error)
        }

        return try Technique(authored: message.technique)
    }

    /// Deleting is idempotent server-side, so there is no refusal to
    /// distinguish: an exercise that was already gone comes back as success.
    public func deleteUserTechnique(id: UserTechniqueId) async throws {
        var request = Ond_V1_DeleteUserTechniqueRequest()
        request.id = id.value

        let response = await client.deleteUserTechnique(request: request)

        guard response.message != nil else {
            throw Self.failure(refused: false, response.transportOutcome, response.error)
        }
    }

    /// Whether the server refused arrives as a flag rather than as a `Code`, for
    /// the reason `ProfileRepository.failure` gives: Connect is OndAPI's
    /// dependency and not this target's. Why it *failed* travels as a
    /// `TransportOutcome`, which `ResponseMessage.transportOutcome` classifies on
    /// the other side of that boundary. A nil error under a nil message would be
    /// a library invariant violation, so the fallback text exists only to keep
    /// this total.
    private static func failure(
        refused: Bool,
        _ outcome: TransportOutcome,
        _ error: (any Error)?
    ) -> UserTechniqueRepositoryError {
        let message = error.responseMessage
        return refused
            ? .rejected(message)
            : .transport(TransportFault(outcome: outcome, diagnostic: message))
    }
}

extension Technique {
    /// The same decoding as a catalogue technique, stamped `.personal`.
    ///
    /// Routed through `init(proto:)` rather than repeated, because every
    /// invariant that decoder enforces — non-empty stages, a phase inside its
    /// own range — is an invariant `SessionTimeline` depends on, and an authored
    /// exercise plays through the same one.
    init(authored proto: Ond_V1_Technique) throws {
        try self.init(proto: proto, origin: .personal)
    }
}

extension TechniqueDraft {
    /// The inverse of [`proto`], for the one thing that receives a draft rather
    /// than sending one: the coach's offer to save a pattern.
    ///
    /// Nil rather than an error, unlike the technique decoders — the server has
    /// already run this draft through the same validator the create RPC uses, so
    /// a card drawn from it is one that call will accept, and every refusal here
    /// is a draft that call would have refused too: a goal or a passage this
    /// build cannot read, or a phase whose `movement` arm is unset, none of
    /// which a server writes and no composer could draw. There is no card to
    /// show for any of them, which is what an offer that never appears is.
    ///
    /// `internal` because `AssistantRepository` is its only caller and the wire
    /// type never leaves this package.
    init?(coachProposal proto: Ond_V1_TechniqueDraft) {
        guard let goal = TechniqueGoal(proto: proto.goal) else { return nil }

        var stages: [DraftStage] = []
        for stage in proto.stages {
            var phases: [DraftPhase] = []
            for phase in stage.phases {
                let movement: Movement
                switch phase.movement {
                case let .inhale(passage):
                    guard let passage = try? Passage(breathing: passage) else { return nil }
                    movement = .inhale(through: passage)
                case let .exhale(passage):
                    guard let passage = try? Passage(breathing: passage) else { return nil }
                    movement = .exhale(through: passage)
                case .hold:
                    movement = .hold
                case .none:
                    return nil
                }
                phases.append(DraftPhase(
                    movement: movement,
                    duration: .milliseconds(Int(phase.durationMs))
                ))
            }
            stages.append(DraftStage(phases: phases, cycles: Int(stage.cycles)))
        }

        self.init(
            name: proto.name,
            summary: proto.summary,
            goal: goal,
            stages: stages,
            rounds: Int(proto.rounds)
        )
    }

    var proto: Ond_V1_TechniqueDraft {
        var message = Ond_V1_TechniqueDraft()
        message.name = name
        message.summary = summary
        message.goal = goal.proto
        message.rounds = UInt32(clamping: rounds)
        message.stages = stages.map { stage in
            var draft = Ond_V1_DraftStage()
            draft.cycles = UInt32(clamping: stage.cycles)
            draft.phases = stage.phases.map { phase in
                var draft = Ond_V1_DraftPhase()
                draft.durationMs = UInt32(clamping: phase.duration.milliseconds)
                // No lungs state on a hold: which of the two it is stored as
                // follows from the breath before it, and the server is the side
                // that decides.
                switch phase.movement {
                case let .inhale(passage): draft.inhale = passage.proto
                case let .exhale(passage): draft.exhale = passage.proto
                case .hold: draft.hold = Ond_V1_Hold()
                }
                return draft
            }
            return draft
        }
        return message
    }
}

extension AuthoringLimits {
    init(proto: Ond_V1_AuthoringLimits) throws {
        // Every count is a floor of one that the contract leaves uncarried, so a
        // server sending zero is one this client cannot compose against at all —
        // a stepper with an empty range traps rather than degrades, and a text
        // field that truncates everything typed into it is the same trap.
        guard proto.maxNameChars >= 1,
              proto.maxSummaryChars >= 1,
              proto.maxStages >= 1,
              proto.maxPhasesPerStage >= 1,
              proto.maxCycles >= 1,
              proto.maxRounds >= 1,
              proto.maxTechniques >= 1
        else {
            throw UserTechniqueRepositoryError.malformedResponse(
                "the authoring limits leave nothing to compose"
            )
        }

        try self.init(
            phases: proto.phases.map(PhaseLimit.init(proto:)),
            maxNameChars: Int(proto.maxNameChars),
            maxSummaryChars: Int(proto.maxSummaryChars),
            maxStages: Int(proto.maxStages),
            maxPhasesPerStage: Int(proto.maxPhasesPerStage),
            cycleRange: 1 ... Int(proto.maxCycles),
            roundRange: 1 ... Int(proto.maxRounds),
            maxTechniques: Int(proto.maxTechniques)
        )
    }
}

extension PhaseLimit {
    init(proto: Ond_V1_PhaseLimit) throws {
        guard let kind = PhaseKind(proto: proto.kind) else {
            throw UserTechniqueRepositoryError.malformedResponse(
                "unrecognised phase kind `\(proto.kind)`"
            )
        }

        // A dial rendered from an inverted range has nowhere to put its handle,
        // and `ClosedRange` traps on one rather than emptying.
        guard proto.minDurationMs > 0, proto.minDurationMs <= proto.maxDurationMs else {
            throw UserTechniqueRepositoryError.malformedResponse(
                "the \(kind) limit is \(proto.minDurationMs)–\(proto.maxDurationMs)ms"
            )
        }

        self.init(
            kind: kind,
            range: .milliseconds(proto.minDurationMs) ... .milliseconds(proto.maxDurationMs)
        )
    }
}
