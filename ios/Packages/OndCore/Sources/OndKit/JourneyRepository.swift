import Foundation
import OndAPI

public enum JourneyRepositoryError: LocalizedError, DiagnosticCarrying, Equatable {
    /// The RPC itself failed — no network, server down, non-OK gRPC status.
    /// Everything the journey does over the network is optional, so a caller's
    /// correct response is almost always to try again later.
    ///
    /// Carries the classified outcome for the person and the transport's own
    /// words for the log — see [`TransportFault`].
    case transport(TransportFault)
    /// The server understood the request and refused it on a condition somebody
    /// can put right. Today that is only `AgeBandUnset`: the decade board asked
    /// for by a profile that has not said which decade. Its own case because
    /// folding it into `.transport` presents the one actionable leaderboard
    /// failure as an outage, to a person with full signal.
    case failedPrecondition(String)
    /// The response parsed but described something this app cannot represent.
    /// Distinct from `.transport` because retrying will not help: the client and
    /// server contracts have diverged.
    case malformedResponse(String)
    /// A value on this device does not fit the field the wire carries it in.
    ///
    /// These numbers come back from `sessions.json` and `bolt-scores.json`,
    /// plain files a person may edit and a backup may restore, and every counter
    /// the proto carries is unsigned 32-bit. Thrown rather than trapped because
    /// `SessionSyncQueue.sync()` runs on every foreground: a trap there is a
    /// crash loop with no way out short of deleting the app.
    ///
    /// What it costs is a sync that stops rather than an app that crashes — the
    /// offending record sits at the head of the queue and everything later waits
    /// behind it. Range-checking where the file is decoded, on `SessionRecord`
    /// itself, would cost one record instead of all of them; this case is as
    /// deep as the wire boundary can put it.
    case malformedRequest(String)

    /// Carries the associated message. Without this conformance
    /// `localizedDescription` bridges to a bare `NSError`, and every log line
    /// and failure banner reading it says "The operation couldn't be completed".
    /// The two malformed cases describe a client and server that have diverged,
    /// which no wording makes actionable — they say the one true thing and leave
    /// the detail to `diagnostic`.
    public var errorDescription: String? {
        switch self {
        case let .transport(fault): fault.outcome.message
        case let .failedPrecondition(message): message
        case .malformedResponse, .malformedRequest:
            "Your practice history arrived in a form the app couldn't read."
        }
    }

    /// What a log records — the transport's own words, kept off the screen.
    public var diagnostic: String {
        switch self {
        case let .transport(fault): fault.diagnostic
        case let .failedPrecondition(message): "the request was refused: \(message)"
        case let .malformedResponse(message): "the response could not be read: \(message)"
        case let .malformedRequest(message): "the request could not be built: \(message)"
        }
    }
}

/// One page of the history the server holds, and where the next one starts.
///
/// A page rather than a list because the restore path asks for the whole
/// archive, not the screen's strip: somebody with years of practice has more
/// sessions than one response should carry, and a single bounded call would hand
/// back the most recent few and call the restore done.
public struct StoredSessionPage: Sendable {
    public let sessions: [SessionRecord]

    /// Pass back to `storedSessions(after:)` for the page behind this one. `nil`
    /// means this page reached the end of the history, which is the only signal
    /// a restore has that it has recovered everything.
    public let nextPageToken: String?

    public init(sessions: [SessionRecord], nextPageToken: String? = nil) {
        self.sessions = sessions
        self.nextPageToken = nextPageToken
    }
}

/// The network side of the journey.
///
/// Everything here is a sync or a genuinely online read. Nothing the Progress tab
/// draws about *this person* goes through it — totals, streaks, and the personal
/// best are folded from the local stores, so the tab is complete with the radio
/// off. Leaderboards are the honest exception: they are other people, and other
/// people need a connection.
public protocol JourneySyncing: Sendable {
    /// Sends sessions the server may not have. Idempotent on each session's id,
    /// so a caller unsure of what landed may simply send it again.
    func record(_ sessions: [SessionRecord]) async throws

    /// Tells the server to forget sessions deleted on this device. Idempotent
    /// on each id, and an id the server never held is not an error — a caller
    /// holding a tombstone is entitled to ask again until it is sure.
    func delete(_ ids: [SessionRecord.ID]) async throws

    /// Sends one controlled-pause score.
    func record(_ score: BoltScore) async throws

    /// Sends one resting-rate measurement.
    func record(_ rate: RestingRate) async throws

    /// One page of the sessions the server holds — the restore path after a
    /// reinstall, where the Keychain identity outlived the local file.
    ///
    /// Asks for the sessions alone. The response's totals, streaks and best
    /// pause are the answer to "who is this person", which a restore does not
    /// need and this app folds from the local stores anyway — and they are the
    /// three heaviest reads the server does, on every page of a walk that
    /// throws them away.
    ///
    /// - Parameter pageToken: `nil` for the newest page, otherwise the
    ///   `nextPageToken` of the page before it. The value is the server's to
    ///   mint and this app's only to carry.
    func storedSessions(after pageToken: String?) async throws -> StoredSessionPage

    func leaderboard(_ board: LeaderboardBoard, scope: LeaderboardScope) async throws -> Leaderboard
}

/// The only type that touches the generated journey types, mirroring
/// `TechniqueRepository` and `ProfileRepository`.
public struct JourneyRepository: JourneySyncing {
    private let client: Ond_V1_JourneyServiceClient

    public init(baseURL: URL, identity: any UserIdentityStore) {
        client = OndClients.journeyService(
            baseURL: baseURL,
            userId: identity.userId,
            sessionCredential: identity.sessionCredential
        )
    }

    public func record(_ sessions: [SessionRecord]) async throws {
        var request = Ond_V1_RecordSessionsRequest()
        // One unrepresentable session fails the batch rather than being dropped
        // from it, matching what the server does with a batch it cannot accept:
        // a send silently short of what the caller handed over is worse than a
        // deferred one. See `malformedRequest` for what that costs.
        request.sessions = try sessions.map { try $0.proto }

        let response = await client.recordSessions(request: request)
        guard response.message != nil else {
            throw Self.failure(
                unmetPrecondition: response.code == .failedPrecondition,
                response.transportOutcome,
                response.error
            )
        }
    }

    public func delete(_ ids: [SessionRecord.ID]) async throws {
        var request = Ond_V1_DeleteSessionsRequest()
        request.clientSessionIds = ids.map(\.uuidString)

        let response = await client.deleteSessions(request: request)
        guard response.message != nil else {
            throw Self.failure(
                unmetPrecondition: response.code == .failedPrecondition,
                response.transportOutcome,
                response.error
            )
        }
    }

    public func record(_ score: BoltScore) async throws {
        var request = Ond_V1_RecordBoltScoreRequest()
        request.clientScoreID = score.id.uuidString
        request.seconds = try onTheWire(score.seconds, "a pause in seconds", of: score.id)
        let measured = try timestampParts(score.measuredAt)
        request.measuredAt.seconds = measured.seconds
        request.measuredAt.nanos = measured.nanos

        let response = await client.recordBoltScore(request: request)
        guard response.message != nil else {
            throw Self.failure(
                unmetPrecondition: response.code == .failedPrecondition,
                response.transportOutcome,
                response.error
            )
        }
    }

    public func record(_ rate: RestingRate) async throws {
        var request = Ond_V1_RecordRestingRateRequest()
        request.clientMeasurementID = rate.id.uuidString
        request.breathsPerMinute = try onTheWire(
            rate.breathsPerMinute,
            "a resting rate in breaths a minute",
            of: rate.id
        )
        let measured = try timestampParts(rate.measuredAt)
        request.measuredAt.seconds = measured.seconds
        request.measuredAt.nanos = measured.nanos

        let response = await client.recordRestingRate(request: request)
        guard response.message != nil else {
            throw Self.failure(
                unmetPrecondition: response.code == .failedPrecondition,
                response.transportOutcome,
                response.error
            )
        }
    }

    /// What one page of a restore asks for.
    ///
    /// Built apart from the call so a test can read it: what this request *says*
    /// is the whole of the contract with the server, and `sessionsOnly` in
    /// particular is unobservable through `JourneySyncing` — a test double
    /// implements the protocol and never sees the message.
    static func restorePage(after pageToken: String?) -> Ond_V1_GetJourneyRequest {
        var request = Ond_V1_GetJourneyRequest()
        request.utcOffsetMinutes = utcOffsetMinutes
        request.limit = restorePageSize
        // On every page, the first included. The server would have no way to
        // tell a restore's opening page from the Progress screen's request
        // otherwise, and that page is the one a short history consists of.
        request.sessionsOnly = true
        if let pageToken {
            request.pageToken = pageToken
        }

        return request
    }

    public func storedSessions(after pageToken: String?) async throws -> StoredSessionPage {
        let response = await client.getJourney(request: Self.restorePage(after: pageToken))
        guard let message = response.message else {
            throw Self.failure(
                unmetPrecondition: response.code == .failedPrecondition,
                response.transportOutcome,
                response.error
            )
        }

        return try StoredSessionPage(
            sessions: message.recentSessions.map { try SessionRecord(proto: $0) },
            nextPageToken: message.hasNextPageToken ? message.nextPageToken : nil
        )
    }

    public func leaderboard(
        _ board: LeaderboardBoard,
        scope: LeaderboardScope
    ) async throws -> Leaderboard {
        var request = Ond_V1_GetLeaderboardRequest()
        request.board = board.proto
        request.scope = scope.proto
        request.utcOffsetMinutes = Self.utcOffsetMinutes

        let response = await client.getLeaderboard(request: request)
        guard let message = response.message else {
            throw Self.failure(
                unmetPrecondition: response.code == .failedPrecondition,
                response.transportOutcome,
                response.error
            )
        }

        return Leaderboard(
            board: board,
            scope: scope,
            entries: message.entries.map {
                LeaderboardEntry(
                    rank: Int($0.rank),
                    displayName: $0.displayName,
                    value: Int($0.value)
                )
            },
            standing: LeaderboardStanding(
                rank: message.caller.hasRank ? Int(message.caller.rank) : nil,
                value: Int(message.caller.value),
                listed: message.caller.listed
            )
        )
    }

    /// How much history one restore page asks for.
    ///
    /// The server's own ceiling, so a restore costs the fewest round trips it
    /// can. Larger than anything a screen would ask for on purpose: the journey
    /// tab's strip is drawn from the local store, and this call exists only for
    /// the device that has no local store yet.
    private static let restorePageSize: UInt32 = 500

    /// Minutes east of UTC, which is the unit every streak the server computes is
    /// expressed in. Read per call rather than stored, so somebody who has flown
    /// gets their new local days on the next request.
    private static var utcOffsetMinutes: Int32 {
        Int32(TimeZone.current.secondsFromGMT() / 60)
    }

    /// The one distinction a caller acts on: whether anything but waiting could
    /// change the answer.
    ///
    /// The status arrives as a flag rather than as a `Code` because Connect is
    /// OndAPI's dependency and not this target's — the same boundary
    /// `timestampParts` keeps with SwiftProtobuf. Every call tests it, not only
    /// the leaderboard's, so a server that begins refusing one of the others on
    /// a condition does not arrive mislabelled as an outage.
    private static func failure(
        unmetPrecondition: Bool,
        _ outcome: TransportOutcome,
        _ error: (any Error)?
    ) -> JourneyRepositoryError {
        let message = error.responseMessage
        return unmetPrecondition
            ? .failedPrecondition(message)
            : .transport(TransportFault(outcome: outcome, diagnostic: message))
    }
}

extension LeaderboardBoard {
    var proto: Ond_V1_LeaderboardBoard {
        switch self {
        case .streak: .streak
        case .minutes30d: .minutes30D
        case .bolt: .bolt
        case .restingRate: .restingRate
        }
    }
}

extension LeaderboardScope {
    var proto: Ond_V1_LeaderboardScope {
        switch self {
        case .global: .global
        case .ageBand: .ageBand
        }
    }
}
