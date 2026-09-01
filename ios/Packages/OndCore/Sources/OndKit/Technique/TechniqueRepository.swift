import Foundation
import OndAPI

public enum TechniqueRepositoryError: LocalizedError, DiagnosticCarrying, Equatable {
    /// The RPC itself failed — no network, server down, non-OK gRPC status.
    ///
    /// Carries the classified outcome for the person and the transport's own
    /// words for the log — see [`TransportFault`].
    case transport(TransportFault)
    /// The response parsed but described something this app cannot represent,
    /// such as a goal it has no case for. Distinct from `.transport` because
    /// retrying will not help: the client and server contracts have diverged.
    case malformedResponse(String)

    /// Carries the associated message. Without this conformance
    /// `localizedDescription` bridges to a bare `NSError`, and every log line
    /// and failure banner reading it says "The operation couldn't be completed".
    public var errorDescription: String? {
        switch self {
        case let .transport(fault): fault.outcome.message
        case .malformedResponse: "The catalogue arrived in a form the app couldn't read."
        }
    }

    /// What a log records — the transport's own words, kept off the screen.
    public var diagnostic: String {
        switch self {
        case let .transport(fault): fault.diagnostic
        case let .malformedResponse(message): "the response could not be read: \(message)"
        }
    }
}

/// Fetches the technique catalogue, the breathing foundations, and the routes
/// into both. Repositories are the only things that touch generated protobuf
/// types: everything above works in `Technique` and `OccasionCatalogue`, so a
/// wire-format change lands here and in `OccasionCatalogue+Decoding` rather
/// than in every view.
public protocol ReferenceFetching: Sendable {
    /// Fetches the complete curated technique catalogue.
    func listTechniques() async throws -> [Technique]

    /// Fetches the complete set of breathing foundations.
    func listFoundations() async throws -> [FoundationTopic]

    /// Fetches the complete set of routes into the catalogue.
    func listOccasions() async throws -> OccasionCatalogue
}

/// Reads a local technique catalogue and refreshes it from its source.
public protocol TechniqueReading: Sendable {
    /// Returns the best catalogue already on the device, if one exists.
    func localTechniques() async -> [Technique]?

    /// Fetches and stores the authoritative catalogue.
    func refreshTechniques() async throws -> [Technique]
}

/// Reads local breathing foundations and refreshes them from their source.
public protocol FoundationReading: Sendable {
    /// Returns the foundations already downloaded to the device, if any.
    func localFoundations() async -> [FoundationTopic]?

    /// Fetches and stores the authoritative foundations.
    func refreshFoundations() async throws -> [FoundationTopic]
}

/// Reads local routes and refreshes them from their source.
public protocol OccasionReading: Sendable {
    /// Returns the best routes already on the device.
    func localOccasions() async -> OccasionCatalogue?

    /// Fetches and stores the authoritative routes.
    func refreshOccasions() async throws -> OccasionCatalogue
}

public struct TechniqueRepository: ReferenceFetching {
    private let client: Ond_V1_TechniqueServiceClient

    /// Takes the identity even though the catalogue is public: the server
    /// creates a person's row on the first RPC of any kind, and this is the
    /// first one the app makes.
    public init(baseURL: URL, identity: any UserIdentityStore) {
        client = OndClients.techniqueService(
            baseURL: baseURL,
            userId: identity.wireUserId,
            sessionCredential: identity.sessionCredential
        )
    }

    public func listTechniques() async throws -> [Technique] {
        let response = await client.listTechniques(request: Ond_V1_ListTechniquesRequest())

        guard let message = response.message else {
            // `ResponseMessage` carries either a message or an error; a nil
            // message with no error would be a library invariant violation, so
            // `responseMessage`'s fallback exists only to keep this total.
            throw TechniqueRepositoryError.transport(TransportFault(
                outcome: response.transportOutcome,
                diagnostic: response.error.responseMessage
            ))
        }

        return try message.techniques.map { try Technique(proto: $0) }
    }

    public func listFoundations() async throws -> [FoundationTopic] {
        let response = await client.listFoundations(request: Ond_V1_ListFoundationsRequest())

        guard let message = response.message else {
            throw TechniqueRepositoryError.transport(TransportFault(
                outcome: response.transportOutcome,
                diagnostic: response.error.responseMessage
            ))
        }

        return message.topics.map(FoundationTopic.init(proto:))
    }

    public func listOccasions() async throws -> OccasionCatalogue {
        let response = await client.listRoutes(request: Ond_V1_ListRoutesRequest())

        guard let message = response.message else {
            throw TechniqueRepositoryError.transport(TransportFault(
                outcome: response.transportOutcome,
                diagnostic: response.error.responseMessage
            ))
        }

        return try OccasionCatalogue(proto: message)
    }
}

extension Technique {
    /// - Parameter origin: which service answered. The wire carries no such
    ///   field — an exercise somebody wrote and a curated one are the same
    ///   message, deliberately, so that one decoder and one `SessionTimeline`
    ///   serve both — so the caller states it, and only
    ///   `UserTechniqueRepository` ever states `.personal`.
    init(proto: Ond_V1_Technique, origin: TechniqueOrigin = .catalogue) throws {
        guard let goal = TechniqueGoal(proto: proto.goal) else {
            throw TechniqueRepositoryError.malformedResponse(
                "technique `\(proto.slug)` has unrecognised goal `\(proto.goal)`"
            )
        }

        guard !proto.stages.isEmpty else {
            throw TechniqueRepositoryError.malformedResponse(
                "technique `\(proto.slug)` has no stages"
            )
        }

        // Zero is the proto default, so it is what a server that predates the
        // field sends. Treating it as a decode failure rather than substituting
        // a guess keeps the same rule the enums follow: a value this app cannot
        // represent — and a session of no rounds is one — never becomes a
        // silent default.
        guard proto.recommendedRounds >= 1 else {
            throw TechniqueRepositoryError.malformedResponse(
                "technique `\(proto.slug)` recommends no rounds"
            )
        }

        try self.init(
            id: TechniqueId(rawValue: proto.id),
            slug: TechniqueSlug(rawValue: proto.slug),
            name: proto.name,
            summary: proto.summary,
            goal: goal,
            stages: proto.stages.map { try Stage(proto: $0, slug: proto.slug) },
            recommendedRounds: Int(proto.recommendedRounds),
            // Handed over as the wire sent them. `Technique.init` is what turns
            // the contract's "empty means nothing written" into nil, so both
            // decode paths and every view can stop asking.
            mechanism: proto.mechanism,
            mechanismContent: proto.hasMechanismContent
                ? ReadingContent(proto: proto.mechanismContent)
                : nil,
            evidence: proto.evidence,
            evidenceContent: proto.hasEvidenceContent
                ? ReadingContent(proto: proto.evidenceContent)
                : nil,
            evidenceGrade: EvidenceGrade(proto: proto.evidenceGrade),
            safetyNote: proto.safetyNote,
            preparation: proto.preparation,
            preparationContent: proto.hasPreparationContent
                ? ReadingContent(proto: proto.preparationContent)
                : nil,
            requires: proto.requiresSubscription ? .catalogue : .free,
            origin: origin
        )
    }
}

extension Stage {
    /// Takes the technique's slug only to name it in a failure — a stage has no
    /// identity of its own beyond its position.
    init(proto: Ond_V1_Stage, slug: String) throws {
        guard !proto.phases.isEmpty else {
            throw TechniqueRepositoryError.malformedResponse(
                "technique `\(slug)` has a stage with no phases"
            )
        }

        guard proto.cycles >= 1 else {
            throw TechniqueRepositoryError.malformedResponse(
                "technique `\(slug)` has a stage playing no cycles"
            )
        }

        try self.init(
            phases: proto.phases.map(Phase.init(proto:)),
            cycles: Int(proto.cycles),
            openEnded: proto.openEnded
        )
    }
}

extension Phase {
    init(proto: Ond_V1_Phase) throws {
        guard let kind = PhaseKind(proto: proto.kind) else {
            throw TechniqueRepositoryError.malformedResponse(
                "unrecognised phase kind `\(proto.kind)`"
            )
        }

        // The dial is rendered from this range, so a range that does not contain
        // its own default leaves a slider with nowhere to put the handle. Same
        // rule as everywhere else on this boundary: reject rather than repair,
        // because a repaired range is a safe limit this app invented.
        guard proto.minDurationMs > 0,
              proto.minDurationMs <= proto.durationMs,
              proto.durationMs <= proto.maxDurationMs
        else {
            throw TechniqueRepositoryError.malformedResponse(
                "a \(proto.durationMs)ms phase sits outside its "
                    + "\(proto.minDurationMs)–\(proto.maxDurationMs)ms range"
            )
        }

        // A gap the contract cannot mean is refused rather than repaired, on
        // the range rule above's terms. This is not the runtime cap: a dial can
        // take a phase under a gap authored for its curated length, and
        // `SessionTurnGap` handles that where the phase is laid out.
        let turnGap = proto.hasTurnGapMs ? Duration.milliseconds(proto.turnGapMs) : nil
        if let turnGap, !SessionTurnGap.authored.contains(turnGap) {
            throw TechniqueRepositoryError.malformedResponse(
                "a phase authors a \(proto.turnGapMs)ms turn gap"
            )
        }

        try self.init(
            Breath(kind: kind, through: proto.passage),
            duration: .milliseconds(proto.durationMs),
            range: .milliseconds(proto.minDurationMs) ... .milliseconds(proto.maxDurationMs),
            manner: Manner(proto: proto.manner),
            turnGap: turnGap,
            // `nilIfEmpty` as well as the presence test: an empty key is the
            // second spelling of absence the column's `CHECK` refuses, and
            // this app should not start holding one either.
            hapticPattern: proto.hasHapticPattern ? proto.hapticPattern.nilIfEmpty : nil
        )
    }
}
