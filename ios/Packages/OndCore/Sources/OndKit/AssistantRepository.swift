import Connect
import Foundation
import OndAPI
import os

/// A failure at the assistant's transport-to-domain boundary.
///
/// Transport failures may recover on retry; malformed responses mean this
/// client cannot represent what the server sent and must not guess.
public enum AssistantRepositoryError: LocalizedError, DiagnosticCarrying, Equatable {
    /// The RPC itself failed — no network, server down, non-OK gRPC status.
    /// Includes `UNAUTHENTICATED`, which is what a call with no readable
    /// Keychain identity comes back as.
    ///
    /// Carries the classified outcome for the person and the transport's own
    /// words for the log — see [`TransportFault`].
    case transport(TransportFault)
    /// The response parsed but described something this app cannot represent.
    /// Distinct from `.transport` because retrying will not help: the client and
    /// server contracts have diverged.
    case malformedResponse(String)

    /// Carries the associated message. Without this conformance
    /// `localizedDescription` bridges to a bare `NSError`, and every log line
    /// and failure banner reading it says "The operation couldn't be completed".
    /// Rarely read: the coach answers a failure with one sentence of its own in
    /// the transcript, and guidance renders nothing at all. It stays correct for
    /// the surface that does show it — the offer card's save.
    public var errorDescription: String? {
        switch self {
        case let .transport(fault): fault.outcome.message
        case .malformedResponse: "The coach's answer arrived in a form the app couldn't read."
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

/// Reads the assistant's guidance.
///
/// The one type that touches the generated assistant types, mirroring
/// `TechniqueRepository` — everything above it works in `Guidance` and
/// `AssistantChunk`, so a change to the wire format is a change to this file.
public protocol AssistantReading: Sendable {
    /// Techniques to try next, best first.
    func recommendations() async throws -> Guidance

    /// The coach's reply to one message, a piece at a time.
    ///
    /// `history` is the transcript so far, oldest first, and the new message
    /// rides separately — the server keeps no conversation state, so every
    /// call carries what the coach should remember. An `AsyncThrowingStream`
    /// keeps the model above testable without a socket.
    func chat(history: [ChatTurn], message: String) -> AsyncThrowingStream<AssistantChunk, Error>
}

/// The generated assistant client translated into OndKit guidance and streams.
///
/// Generated protobuf values stop here. Callers receive domain types and one
/// streaming abstraction whose termination always reflects the final gRPC
/// status.
public struct AssistantRepository: AssistantReading {
    private static let logger = Logger(category: "assistant")

    private let client: Ond_V1_AssistantServiceClient
    private let healthContext: @Sendable () async -> CoachHealthContext?

    /// `healthContext` is asked immediately before each request and its answer
    /// attached to that request alone — never cached here, because the person
    /// can withdraw the opt-in between two calls and the very next request
    /// must already carry nothing. The default provider answers nil, which is
    /// a request identical to one from a build that predates health context.
    ///
    /// - Parameters:
    ///   - baseURL: The API origin used by the generated client.
    ///   - identity: The current user id and optional signed-in credential,
    ///     re-read for every request by the interceptor.
    ///   - healthContext: A fresh, opted-in summary for the next request, or
    ///     `nil` when Health sharing is unavailable or disabled.
    public init(
        baseURL: URL,
        identity: any UserIdentityStore,
        healthContext: @escaping @Sendable () async -> CoachHealthContext? = { nil }
    ) {
        client = OndClients.assistantService(
            baseURL: baseURL,
            userId: identity.userId,
            sessionCredential: identity.sessionCredential
        )
        self.healthContext = healthContext
    }

    /// Fetches ranked guidance, attaching the latest opted-in health context.
    public func recommendations() async throws -> Guidance {
        var request = Ond_V1_GetRecommendationRequest()
        if let context = await healthContext() {
            request.healthContext = Self.wire(context)
        }
        let response = await client.getRecommendation(request: request)

        guard let message = response.message else {
            throw AssistantRepositoryError.transport(TransportFault(
                outcome: response.transportOutcome,
                diagnostic: response.error.responseMessage
            ))
        }

        guard let source = GuidanceSource(proto: message.source) else {
            throw AssistantRepositoryError.malformedResponse(
                "unrecognised guidance source `\(message.source)`"
            )
        }

        // Total, unlike the technique decoders: both fields are strings the app
        // only displays, and the server has already guaranteed the slug is one
        // the catalogue holds.
        let recommendations = message.recommendations.map {
            Recommendation(techniqueSlug: $0.techniqueSlug, reason: $0.reason)
        }

        guard !recommendations.isEmpty else {
            throw AssistantRepositoryError.malformedResponse("the guidance was empty")
        }

        return Guidance(recommendations: recommendations, source: source)
    }

    /// Streams one coach reply while preserving terminal transport failures.
    ///
    /// - Parameters:
    ///   - history: The transcript so far, oldest first.
    ///   - message: The person's new message.
    public func chat(
        history: [ChatTurn],
        message: String
    ) -> AsyncThrowingStream<AssistantChunk, Error> {
        Self.bridged(client.chat(), request: { [healthContext] in
            var request = Ond_V1_ChatRequest()
            request.history = history.map(Self.wire)
            request.message = message
            if let context = await healthContext() {
                request.healthContext = Self.wire(context)
            }
            // Only this RPC carries one, and only so the coach can name a
            // streak. Read per call, `JourneyRepository`'s rule: somebody who
            // has flown gets their new local days on the next question, and the
            // number the coach says stays the number Home shows.
            request.utcOffsetMinutes = Int32(TimeZone.current.secondsFromGMT() / 60)
            return request
        }, chunk: { response in
            Self.chunk(
                text: response.text,
                source: response.source,
                proposal: Self.proposal(response)
            )
        })
    }

    /// Bridges one Connect server stream into an `AsyncThrowingStream` —
    /// written once because the subtle parts must not be able to drift
    /// between RPCs.
    ///
    /// Connect hands back a stream you must `send` the request on exactly once
    /// to start, then read `results()` from. Both halves are wrapped here so
    /// nothing above this file learns that shape — and, more usefully, so the
    /// terminal `.complete` carrying a non-OK code becomes a thrown error
    /// rather than a stream that simply stops, which is indistinguishable from
    /// a short answer.
    ///
    /// The request is built *inside* the reader task, because the health
    /// provider it awaits is async and the stream closure cannot suspend —
    /// the summary is read from Health at the moment of the request.
    /// The three ways this bridge fails, built in one place — inline they cost
    /// the reader four lines each in the middle of the loop they interrupt.
    private static func streamFailure(
        _ outcome: TransportOutcome,
        _ diagnostic: String
    ) -> AssistantRepositoryError {
        .transport(TransportFault(outcome: outcome, diagnostic: diagnostic))
    }

    static func bridged<Request, Response>(
        _ stream: any ServerOnlyAsyncStreamInterface<Request, Response>,
        request: @escaping @Sendable () async -> Request,
        chunk: @escaping @Sendable (Response) -> Result<AssistantChunk, AssistantRepositoryError>
    ) -> AsyncThrowingStream<AssistantChunk, Error> {
        AsyncThrowingStream { continuation in
            let reader = Task {
                do {
                    try await stream.send(request())
                } catch {
                    continuation.finish(throwing: streamFailure(
                        TransportOutcome(error: error),
                        error.localizedDescription
                    ))
                    return
                }

                for await result in stream.results() {
                    switch result {
                    case let .message(message):
                        switch chunk(message) {
                        case let .success(chunk):
                            continuation.yield(chunk)
                        case let .failure(error):
                            continuation.finish(throwing: error)
                            return
                        }

                    case let .complete(code, error, _):
                        if code == .ok {
                            continuation.finish()
                        } else {
                            continuation.finish(throwing: streamFailure(
                                TransportOutcome(code: code),
                                error?.localizedDescription
                                    ?? "the stream ended with \(code)"
                            ))
                        }
                        return

                    case .headers:
                        continue
                    }
                }

                // The results ran out without a `.complete`, which the library
                // should not do. Finishing cleanly would present whatever
                // arrived as the whole answer — the "a stream that stops is
                // indistinguishable from a short one" hazard this wrapper
                // exists to close, and the only live way to reach this line:
                // after a reader cancels, `onTermination` has already finished
                // the continuation and this throw is a no-op.
                continuation.finish(throwing: streamFailure(
                    .serverFault,
                    "the stream ended without a status"
                ))
            }

            // A view that goes away mid-answer must not leave the request
            // running: cancelling the read stops the loop, and `cancel()` tells
            // the server to stop writing.
            continuation.onTermination = { _ in
                reader.cancel()
                stream.cancel()
            }
        }
    }

    /// One wire chunk as the domain chunk, or the refusal every enum on this
    /// boundary earns — an unrepresentable source is a decode failure, never
    /// a guess.
    private static func chunk(
        text: String,
        source proto: Ond_V1_AssistantSource,
        proposal: CoachProposal? = nil
    ) -> Result<AssistantChunk, AssistantRepositoryError> {
        guard let source = GuidanceSource(proto: proto) else {
            return .failure(.malformedResponse("unrecognised guidance source `\(proto)`"))
        }
        return .success(AssistantChunk(text: text, source: source, proposal: proposal))
    }

    /// The chunk's proposal, or nil — tolerantly, unlike the source above: a
    /// malformed proposal decorates a reply that is already good, so it is
    /// dropped and the text kept rather than failing the stream over a card.
    ///
    /// An unrecognised arm reads as no proposal for the same reason. A newer
    /// server offering something this build has no card for should leave the
    /// person with the coach's prose, which stands on its own by contract.
    ///
    /// `internal` on `bridged`'s terms: the decode rules are worth pinning and
    /// the wire type never leaves this package.
    static func proposal(_ response: Ond_V1_ChatResponse) -> CoachProposal? {
        switch response.payload {
        case .boltTest:
            return .boltTest
        case .offer:
            return offer(response).map(CoachProposal.exercise)
        case let .savedExercise(draft):
            guard let decoded = TechniqueDraft(coachProposal: draft) else {
                Self.logger.notice(
                    "a saved-exercise proposal could not be decoded; keeping the reply prose"
                )
                return nil
            }
            return .savedExercise(decoded)
        case .text, .none:
            return nil
        }
    }

    static func offer(_ response: Ond_V1_ChatResponse) -> ExerciseOffer? {
        guard case let .offer(wire) = response.payload, !wire.techniqueSlug.isEmpty else {
            return nil
        }

        // An offer with no overrides message — or an empty one — is "as
        // catalogued". A mismatch against this device's (possibly older)
        // catalogue is `dialled(with:)`'s to absorb, not this decoder's.
        let overrides: TechniqueOverrides? =
            if wire.hasOverrides, !wire.overrides.stages.isEmpty {
                TechniqueOverrides(
                    stages: wire.overrides.stages.map { stage in
                        StageDialling(
                            phaseDurationsMs: stage.phaseDurationsMs.map(Int.init),
                            cycles: Int(stage.cycles)
                        )
                    },
                    rounds: Int(wire.overrides.rounds)
                )
            } else {
                nil
            }

        return ExerciseOffer(techniqueSlug: wire.techniqueSlug, overrides: overrides)
    }

    /// The domain turn as the wire message. Total in this direction: every
    /// domain role has a wire value, so nothing the app holds can fail to be
    /// read back — a history turn past the message bound included, because
    /// the server truncates replayed turns rather than refusing them. The
    /// offer travels as its slug alone — the server's history annotation
    /// needs to know what was offered, never the numbers. `internal` on
    /// [`offer(_:)`]'s terms.
    static func wire(_ turn: ChatTurn) -> Ond_V1_ChatTurn {
        var wire = Ond_V1_ChatTurn()
        wire.role =
            switch turn.role {
            case .person: .person
            case .coach: .coach
            }
        wire.text = turn.text
        if let offer = turn.offer {
            wire.offeredSlug = offer.techniqueSlug
        }
        return wire
    }

    /// The domain summary as the wire message, metric by metric. A snapshot's
    /// nil trend stays an absent field — the server reads absence as "too
    /// little evidence", which is exactly what it was. `clamping` because the
    /// values are whole-unit physiological means: anything an `Int32` cannot
    /// hold is a corrupt reading, and the server's range clamp drops it there.
    private static func wire(_ context: CoachHealthContext) -> Ond_V1_HealthContext {
        var wire = Ond_V1_HealthContext()
        if let breathing = context.sleepingBreathingRate {
            wire.sleepingBreathsPerMinute = Int32(clamping: breathing.sevenDayMean)
            if let trend = breathing.trendFromBaseline {
                wire.sleepingBreathsTrend = Int32(clamping: trend)
            }
        }
        if let resting = context.restingHeartRate {
            wire.restingHrBpm = Int32(clamping: resting.sevenDayMean)
            if let trend = resting.trendFromBaseline {
                wire.restingHrTrendBpm = Int32(clamping: trend)
            }
        }
        if let variability = context.heartRateVariability {
            wire.hrvSdnnMs = Int32(clamping: variability.sevenDayMean)
            if let trend = variability.trendFromBaseline {
                wire.hrvSdnnTrendMs = Int32(clamping: trend)
            }
        }
        return wire
    }
}

extension GuidanceSource {
    /// Returns nil for `UNSPECIFIED` and for any case added after this app
    /// shipped — the same rule every enum on this boundary follows. Guessing
    /// `.fallback` would be the safer-looking default and the wrong one: it
    /// would have the app claim the server said something it did not.
    init?(proto: Ond_V1_AssistantSource) {
        switch proto {
        case .model: self = .model
        case .fallback: self = .fallback
        case .subscriptionRequired: self = .subscriptionRequired
        case .unspecified, .UNRECOGNIZED: return nil
        }
    }
}
